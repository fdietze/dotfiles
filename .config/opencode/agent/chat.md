---
description: Generic Chat
mode: primary
# model: google/gemini-3.1-pro-preview
# model: google/gemini-2.5-pro
model: openrouter/openai/gpt-5.4
# model: openrouter/z-ai/glm-5
# model: openrouter/google/gemini-3-pro-preview
# temperature: 0.0
permission:  
  read: allow  
  grep: allow  
  glob: allow  
  list: allow  
  webfetch: allow  
  lsp: allow  
  question: deny  
  bash: deny  
  todowrite: deny  
  session: deny  
  edit:  
    "*": deny  
    "docs/**/*.md": allow  
    "*.md": allow  
  task:  
    "*": deny
---

You are a generic helpful assistant.
