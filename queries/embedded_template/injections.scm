;; extends

; Inject HTML into content nodes (text outside <% %> tags).
; Each (content) fragment is parsed as an independent HTML document.
; We intentionally do NOT use injection.combined here. With combined injection,
; Neovim builds a virtual merged document and then has to map CSS (and JS)
; sub-injection positions back through two offset layers, which causes the
; CSS highlights inside <style> blocks to land at wrong buffer positions.
; Without combined, each fragment is its own HTML parse, and <style> blocks
; that contain no EJS tags (the common case) live in one complete fragment
; that the HTML parser can inject CSS into correctly.
((content) @injection.content
 (#set! injection.language "html"))

; Inject JavaScript into code nodes inside <% %> scriptlet blocks.
(directive
  (code) @injection.content
  (#set! injection.language "javascript"))

; Inject JavaScript into code nodes inside <%= %> and <%- %> output blocks.
(output_directive
  (code) @injection.content
  (#set! injection.language "javascript"))
