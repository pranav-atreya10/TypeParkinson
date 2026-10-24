'use strict';
(() => {
  const input = document.getElementById('demo-input');
  if (!input) return;
  const status = document.getElementById('demo-status');
  const undo = document.getElementById('demo-revert');
  const examples = new Map([['tje', 'the'], ['hellloo', 'hello'], ['tomorow', 'tomorrow'], ['teh', 'the']]);
  let previous = null;
  function resetCorrection() { previous = null; undo.hidden = true; }
  function commit() {
    const match = input.value.match(/([a-z]+)(\s+)$/i);
    resetCorrection();
    if (!match) { status.textContent = 'Choose one of the four examples to try a correction.'; return; }
    const original = match[1];
    let word = examples.get(original.toLowerCase());
    if (!word) { status.textContent = 'This word is outside the four-example illustration.'; return; }
    if (original === original.toUpperCase()) word = word.toUpperCase();
    else if (/^[A-Z]/.test(original)) word = word[0].toUpperCase() + word.slice(1);
    previous = input.value;
    input.value = input.value.slice(0, match.index) + word + match[2];
    status.textContent = `“${original}” became “${word}”. You can undo it.`;
    undo.hidden = false;
  }
  input.addEventListener('input', () => {
    resetCorrection();
    if (/\s$/.test(input.value)) commit();
    else status.textContent = 'Press space to see the idea.';
  });
  document.querySelectorAll('[data-example]').forEach(button => button.addEventListener('click', () => {
    input.value = button.dataset.example;
    resetCorrection(); status.textContent = 'Press space to see the idea.';
    input.focus(); input.setSelectionRange(input.value.length, input.value.length);
  }));
  document.querySelectorAll('[data-key]').forEach(button => button.addEventListener('click', () => {
    const key = button.dataset.key;
    const start = input.selectionStart ?? input.value.length;
    const end = input.selectionEnd ?? start;
    let cursor;
    if (key === 'Backspace') {
      const from = start === end ? Math.max(0, start - 1) : start;
      input.value = input.value.slice(0, from) + input.value.slice(end); cursor = from;
    } else {
      if (input.value.length - (end - start) + key.length > input.maxLength) return;
      input.value = input.value.slice(0, start) + key + input.value.slice(end); cursor = start + key.length;
    }
    resetCorrection(); status.textContent = 'Press space to see the idea.';
    // Only commit at the end; preserve editing and selection in the middle of a sentence.
    if (key === ' ' && cursor === input.value.length) { commit(); cursor = input.value.length; }
    input.setSelectionRange(cursor, cursor);
  }));
  undo.addEventListener('click', () => {
    if (previous === null) return;
    input.value = previous; resetCorrection(); status.textContent = 'Original word restored.';
    input.focus(); input.setSelectionRange(input.value.length, input.value.length);
  });
  document.getElementById('demo-clear').addEventListener('click', () => {
    input.value = ''; resetCorrection(); status.textContent = 'Choose an example or type your own words.'; input.focus();
  });
})();
