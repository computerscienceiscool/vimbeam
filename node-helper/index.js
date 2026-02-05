#!/usr/bin/env node
/**
 * Neovim <-> Automerge Bridge
 * 
 * This helper speaks the real Automerge sync protocol to the collaboration
 * server, and communicates with Neovim via simple JSON over stdin/stdout.
 * 
 * Usage:
 *   node index.js
 *   Then send JSON commands on stdin, receive responses on stdout.
 */

import { Repo } from '@automerge/automerge-repo';
import { BrowserWebSocketClientAdapter } from '@automerge/automerge-repo-network-websocket';
import { NodeFSStorageAdapter } from '@automerge/automerge-repo-storage-nodefs';
import { next as Automerge } from '@automerge/automerge';
import * as readline from 'readline';
import * as path from 'path';
import * as os from 'os';
import * as fs from 'fs';
import { AwarenessClientNode } from '@collab-editor/awareness/node';

// State
let repo = null;
let handle = null;
let awarenessClient = null;
let userId = null;
let userName = 'vimbeam-user';
let userColor = '#88cc88';
let currentDocId = null;
let isApplyingRemote = false;
let currentSelection = { anchor: 0 };
let changeHandler = null;  // Track change listener for cleanup

// Storage directory for Automerge data
const storageDir = path.join(os.homedir(), '.local', 'share', 'vimbeam', 'automerge-data');

// Ensure storage directory exists
if (!fs.existsSync(storageDir)) {
  fs.mkdirSync(storageDir, { recursive: true });
}

// Setup readline for stdin
const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  terminal: false
});

/**
 * Send a message to Neovim (stdout)
 */
function send(obj) {
  console.log(JSON.stringify(obj));
}

/**
 * Log to stderr (doesn't interfere with JSON protocol)
 */
function log(msg) {
  process.stderr.write(`[helper] ${msg}\n`);
}

/**
 * Convert document content to a plain string
 */
function contentToString(doc) {
  if (!doc || doc.content === undefined) return '';
  const value = doc.content;
  if (typeof value === 'string') return value;
  if (value && typeof value.toString === 'function') {
    try {
      return value.toString();
    } catch (e) {
      log(`contentToString toString error: ${e.message}`);
      return '';
    }
  }
  try {
    return String(value);
  } catch (e) {
    log(`contentToString String() error: ${e.message}`);
    return '';
  }
}

/**
 * Generate a simple user ID
 */
function generateUserId() {
  return 'beam-' + Math.random().toString(36).substring(2, 10);
}

/**
 * Connect to the awareness server using AwarenessClientNode
 */
function connectAwareness(url) {
  if (awarenessClient) {
    awarenessClient.destroy();
    awarenessClient = null;
  }

  awarenessClient = new AwarenessClientNode(url, {
    userId: userId,
    name: userName,
    color: userColor,
    documentId: currentDocId || 'default'
  });

  awarenessClient.on('connected', () => {
    log('Awareness connected');
  });

  awarenessClient.on('cursor', (data) => {
    // Forward cursor updates to Neovim
    const displayName = (data.name || '').trim() || data.userId || 'unknown';
    send({
      type: 'cursor',
      userId: data.userId,
      name: displayName,
      color: data.color || '#888888',
      anchor: data.anchor ?? null,
      head: data.head ?? null
    });
  });

  awarenessClient.on('disconnected', () => {
    log('Awareness disconnected');
  });

  awarenessClient.on('error', (err) => {
    log(`Awareness error: ${err?.message || err}`);
  });

  awarenessClient.connect();
}

/**
 * Send awareness (presence/cursor) info
 */
let currentCursorOffset = 0;

function sendAwareness(selection = null) {
  const selectionState = selection || currentSelection || { anchor: currentCursorOffset };
  log('sendAwareness called, selection anchor=' + selectionState.anchor + (selectionState.head !== undefined ? ` head=${selectionState.head}` : ''));

  if (awarenessClient) {
    if (selectionState.head !== undefined) {
      awarenessClient.updateSelection(selectionState.anchor, selectionState.head);
    } else {
      awarenessClient.updateCursor(selectionState.anchor);
    }
  }
}

/**
 * Handle incoming messages from Neovim
 */
async function handleMessage(msg) {
  try {
    switch (msg.type) {
      case 'connect': {
        userId = generateUserId();
        if (msg.name) {
          userName = msg.name;
        }
        if (msg.color) {
          userColor = msg.color;
        }
        
        // Create Automerge repo with WebSocket sync
        repo = new Repo({
          network: [new BrowserWebSocketClientAdapter(msg.syncUrl)],
          storage: new NodeFSStorageAdapter(storageDir),
        });

        // Connect to awareness server if provided
        if (msg.awarenessUrl) {
          connectAwareness(msg.awarenessUrl);
        }

        send({ type: 'connected', userId: userId });
        log(`Connected to ${msg.syncUrl}`);
        break;
      }

      case 'disconnect': {
        // Clean up change listener
        if (handle && changeHandler) {
          handle.off('change', changeHandler);
          changeHandler = null;
        }
        if (handle) {
          handle = null;
        }
        if (awarenessClient) {
          awarenessClient.destroy();
          awarenessClient = null;
        }
        if (repo) {
          repo = null;
        }
        send({ type: 'disconnected' });
        log('Disconnected');
        break;
      }

      case 'create': {
        if (!repo) {
          send({ type: 'error', message: 'Not connected' });
          break;
        }

        // Create new document
        handle = repo.create();
        handle.change(d => {
          d.content = '';
        });

        const docId = handle.documentId;
        currentDocId = docId;

        // Setup change listener
        setupChangeListener();

        // Update awareness client's document ID and broadcast
        if (awarenessClient) {
          awarenessClient.setDocumentId(docId);
        }
        sendAwareness();

        send({ type: 'created', docId: docId });
        log(`Created document: ${docId}`);
        break;
      }

      case 'open': {
        if (!repo) {
          send({ type: 'error', message: 'Not connected' });
          break;
        }

        const docId = msg.docId;
        log(`Opening document: ${docId}`);

        try {
          // Find the document (repo.find is async in v2)
          const fullDocId = docId.startsWith('automerge:') ? docId : `automerge:${docId}`;
          // Repo.find resolves when the handle is ready in v2
          handle = await repo.find(fullDocId);
          await handle.whenReady();
          
          // Check if we got content from local storage
          let doc = handle.doc();
          let content = contentToString(doc);
          
          // If empty, wait for sync server to send the real content
          if (content === '') {
            log('Local storage empty, waiting for sync...');

            content = await new Promise((resolve) => {
              const timeout = setTimeout(() => {
                handle.off('change', syncHandler);
                resolve('');
              }, 8000);

              // Named handler so we can remove it after sync
              const syncHandler = ({ doc }) => {
                const c = contentToString(doc);
                if (c !== '') {
                  clearTimeout(timeout);
                  handle.off('change', syncHandler);
                  resolve(c);
                }
              };

              handle.on('change', syncHandler);
            });
          }

          // Setup change listener
          setupChangeListener();
          currentDocId = fullDocId;  // Use full ID with automerge: prefix for awareness matching

          // Update awareness client's document ID and broadcast
          if (awarenessClient) {
            awarenessClient.setDocumentId(fullDocId);
          }
          sendAwareness();

          send({ type: 'opened', docId: fullDocId, content: content });
          log(`Opened document: ${docId} (${content.length} chars)`);

          // Fallback: if initial content was empty, re-check after sync settles
          setTimeout(() => {
            try {
              if (!handle) return;
              const latest = contentToString(handle.doc());
              if (latest && latest !== content) {
                isApplyingRemote = true;
                send({ type: 'changed', content: latest });
                isApplyingRemote = false;
                log(`Delayed content sync delivered (${latest.length} chars)`);
              }
            } catch (e) {
              log(`Delayed content check failed: ${e.message}`);
            }
          }, 3000);
        } catch (e) {
          send({ type: 'error', message: `Failed to open: ${e.message}` });
          log(`Open failed: ${e.message}`);
        }
        break;
      }

      case 'edit': {
        if (!handle) {
          send({ type: 'error', message: 'No document open' });
          break;
        }

        if (isApplyingRemote) {
          break;
        }

        const newContent = msg.content;

        try {
          handle.change(d => {
            // Use Automerge.updateText for proper CRDT merge (not full replacement)
            // This ensures offline edits merge correctly on reconnect
            Automerge.updateText(d, ['content'], newContent);
          });
          log(`Edit applied (${newContent.length} chars)`);
        } catch (err) {
          send({ type: 'error', message: `Edit failed: ${err.message}` });
          log(`Edit failed: ${err.message}`);
        }
        break;
      }

      case 'close': {
        // Clean up change listener before releasing handle
        if (handle && changeHandler) {
          handle.off('change', changeHandler);
          changeHandler = null;
        }
        handle = null;
        send({ type: 'closed' });
        log('Document closed');
        break;
      }

      case 'set_name': {
        userName = msg.name || 'vimbeam-user';
        if (awarenessClient) {
          awarenessClient.setName(userName);
        }
        send({ type: 'name_set', name: userName });
        log(`Name set to: ${userName}`);
        break;
      }

      case 'set_color': {
        userColor = msg.color || '#88cc88';
        if (awarenessClient) {
          awarenessClient.setColor(userColor);
        }
        send({ type: 'color_set', color: userColor });
        log(`Color set to: ${userColor}`);
        break;
      }

      case 'cursor': {
        const docLen = contentToString(handle?.doc()).length;
        const offset = Math.max(0, Math.min(Number(msg.offset) || 0, docLen));
        currentCursorOffset = offset;

        if (msg.selection && typeof msg.selection === 'object') {
          const anchor = Math.max(0, Math.min(Number(msg.selection.anchor) || 0, docLen));
          const headRaw = msg.selection.head;
          const head = headRaw === undefined ? anchor : Math.max(0, Math.min(Number(headRaw) || 0, docLen));
          currentSelection = { anchor, head };
        } else {
          currentSelection = { anchor: offset };
        }

        sendAwareness();
        break;
      }

      case 'info': {
        send({
          type: 'info',
          connected: repo !== null,
          docId: handle?.documentId || null,
          userId: userId,
          userName: userName
        });
        break;
      }

      default:
        send({ type: 'error', message: `Unknown message type: ${msg.type}` });
    }
  } catch (e) {
    send({ type: 'error', message: e.message });
    log(`Error: ${e.message}`);
  }
}

/**
 * Setup listener for remote changes
 * Removes previous listener to prevent accumulation
 */
function setupChangeListener() {
  if (!handle) return;

  // Remove previous listener to prevent accumulation
  if (changeHandler) {
    handle.off('change', changeHandler);
    changeHandler = null;
  }

  // Create named handler for cleanup capability
  changeHandler = ({ doc }) => {
    const content = contentToString(doc);

    isApplyingRemote = true;
    send({ type: 'changed', content: content });
    isApplyingRemote = false;

    log(`Remote change received (${content.length} chars)`);
  };

  handle.on('change', changeHandler);
}

// Message queue for serialized processing
// Prevents concurrent handleMessage() calls during rapid input (e.g., offline reconnect)
const messageQueue = [];
let isProcessingQueue = false;

async function processQueue() {
  if (isProcessingQueue) return;
  isProcessingQueue = true;

  while (messageQueue.length > 0) {
    const msg = messageQueue.shift();
    try {
      await handleMessage(msg);
    } catch (e) {
      send({ type: 'error', message: `Handler error: ${e.message}` });
      log(`Handler error: ${e.message}`);
    }
  }

  isProcessingQueue = false;
}

// Process stdin line by line
rl.on('line', (line) => {
  if (!line.trim()) return;

  try {
    const msg = JSON.parse(line);
    messageQueue.push(msg);
    processQueue();
  } catch (e) {
    send({ type: 'error', message: `Parse error: ${e.message}` });
    log(`Parse error: ${e.message}`);
  }
});

rl.on('close', () => {
  log('stdin closed, exiting');
  process.exit(0);
});

// Handle process signals
process.on('SIGINT', () => {
  log('SIGINT received, exiting');
  process.exit(0);
});

process.on('SIGTERM', () => {
  log('SIGTERM received, exiting');
  process.exit(0);
});

log('Helper started, waiting for commands...');
