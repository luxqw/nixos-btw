// ==UserScript==
// @name         Bionic Reading
// @namespace    https://github.com/luxqw/nixos-btw
// @version      1.0.0
// @description  Bolds the first ~40% of every word to guide the eye. Toggle with Ctrl+Alt+B.
// @author       luxqw
// @license      MIT
// @match        *://*/*
// @run-at       document-idle
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_addValueChangeListener
// @grant        GM_registerMenuCommand
// @grant        GM_addStyle
// @downloadURL  https://raw.githubusercontent.com/luxqw/nixos-btw/main/userscripts/bionic-reading.user.js
// @updateURL    https://raw.githubusercontent.com/luxqw/nixos-btw/main/userscripts/bionic-reading.user.js
// ==/UserScript==

// Marked-up text nodes are wrapped in a <bionic-text> element whose textContent
// still equals the original text, so switching off restores the page exactly.
// A site that keeps its own reference to a text node we replaced will write into
// a detached node -- rare, and a reload fixes it.

(() => {
  "use strict";

  // Share of each word that gets bolded. Words of 1-3 letters always get one.
  const FIXATION = 0.4;
  const DEBOUNCE_MS = 150;
  const CHUNK_SIZE = 200;
  const STATE_KEY = "enabled";

  const SKIP_SELECTOR = [
    "code",
    "pre",
    "kbd",
    "samp",
    "var",
    "tt",
    "script",
    "style",
    "noscript",
    "svg",
    "math",
    "canvas",
    "textarea",
    "input",
    "select",
    "option",
    '[contenteditable=""]',
    '[contenteditable="true"]',
    "[hidden]",
    '[aria-hidden="true"]',
    "bionic-text",
  ].join(",");

  const WORD = /[\p{L}\p{M}\p{Nd}]+/gu;
  const HAS_LETTER = /\p{L}/u;

  const idle =
    window.requestIdleCallback || ((fn) => setTimeout(() => fn(), 16));

  let enabled = GM_getValue(STATE_KEY, false);
  let observer = null;
  let pending = new Set();
  let timer = null;

  GM_addStyle(".bionic-fix { font-weight: 700 !important; }");

  const prefixLength = (length) =>
    length <= 3 ? 1 : Math.ceil(length * FIXATION);

  const isMarkable = (node) => {
    if (!HAS_LETTER.test(node.nodeValue)) return false;
    const parent = node.parentElement;
    return Boolean(parent) && !parent.closest(SKIP_SELECTOR);
  };

  const markTextNode = (node) => {
    const text = node.nodeValue;
    const fragment = document.createDocumentFragment();
    let last = 0;
    let marked = false;

    WORD.lastIndex = 0;
    for (let match; (match = WORD.exec(text)); ) {
      const word = match[0];
      if (!HAS_LETTER.test(word)) continue;

      if (match.index > last) fragment.append(text.slice(last, match.index));

      const cut = prefixLength(word.length);
      const bold = document.createElement("span");
      bold.className = "bionic-fix";
      bold.textContent = word.slice(0, cut);
      fragment.append(bold);
      if (cut < word.length) fragment.append(word.slice(cut));

      last = match.index + word.length;
      marked = true;
    }

    if (!marked) return;
    if (last < text.length) fragment.append(text.slice(last));

    const wrapper = document.createElement("bionic-text");
    wrapper.append(fragment);
    node.parentNode.replaceChild(wrapper, node);
  };

  const collect = (root) => {
    if (root.nodeType === Node.TEXT_NODE) {
      return isMarkable(root) ? [root] : [];
    }
    if (root.nodeType !== Node.ELEMENT_NODE) return [];

    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) =>
        isMarkable(node) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT,
    });

    const nodes = [];
    for (let node; (node = walker.nextNode()); ) nodes.push(node);
    return nodes;
  };

  const markAll = (roots) => {
    const nodes = [];
    for (const root of roots) {
      if (root.isConnected) nodes.push(...collect(root));
    }
    if (!nodes.length) return;

    const step = () => {
      for (const node of nodes.splice(0, CHUNK_SIZE)) {
        if (node.isConnected) markTextNode(node);
      }
      // Drop the records our own edits just produced.
      if (observer) observer.takeRecords();
      if (nodes.length) idle(step);
    };
    step();
  };

  const unmarkAll = () => {
    for (const wrapper of document.querySelectorAll("bionic-text")) {
      const parent = wrapper.parentNode;
      if (!parent) continue;
      parent.replaceChild(document.createTextNode(wrapper.textContent), wrapper);
      parent.normalize();
    }
  };

  const scheduleScan = () => {
    clearTimeout(timer);
    timer = setTimeout(() => {
      const roots = pending;
      pending = new Set();
      markAll(roots);
    }, DEBOUNCE_MS);
  };

  const start = () => {
    if (!document.body || observer) return;

    markAll([document.body]);

    observer = new MutationObserver((records) => {
      for (const record of records) {
        if (record.type === "characterData") {
          if (isMarkable(record.target)) pending.add(record.target);
          continue;
        }
        for (const node of record.addedNodes) {
          if (
            node.nodeType === Node.ELEMENT_NODE ||
            node.nodeType === Node.TEXT_NODE
          ) {
            pending.add(node);
          }
        }
      }
      if (pending.size) scheduleScan();
    });

    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
      characterData: true,
    });
  };

  const stop = () => {
    if (observer) {
      observer.disconnect();
      observer = null;
    }
    clearTimeout(timer);
    pending.clear();
    unmarkAll();
  };

  const apply = (value) => {
    enabled = value;
    if (enabled) start();
    else stop();
  };

  const toggle = () => {
    const next = !enabled;
    GM_setValue(STATE_KEY, next);
    apply(next);
  };

  GM_addValueChangeListener(STATE_KEY, (_key, _old, value, remote) => {
    if (remote) apply(value);
  });

  GM_registerMenuCommand("Bionic reading: toggle (Ctrl+Alt+B)", toggle);

  // event.code so the binding survives a non-Latin keyboard layout.
  window.addEventListener(
    "keydown",
    (event) => {
      if (
        event.ctrlKey &&
        event.altKey &&
        !event.shiftKey &&
        !event.metaKey &&
        event.code === "KeyB"
      ) {
        event.preventDefault();
        toggle();
      }
    },
    true,
  );

  if (enabled) apply(true);
})();
