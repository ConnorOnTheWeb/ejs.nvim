;; extends

; Inject HTML into content nodes (text outside <% %> tags).
; injection.combined merges all content fragments into one HTML document.
((content) @injection.content
 (#set! injection.language "html")
 (#set! injection.combined))

; Inject JavaScript into code nodes inside <% %> scriptlet blocks.
; Each block is parsed as an independent JS fragment -- do NOT use
; injection.combined here. Combining disconnected scriptlet blocks produces
; invalid JavaScript and causes the parser to return an error tree with no
; highlights.
(directive
  (code) @injection.content
  (#set! injection.language "javascript"))

; Inject JavaScript into code nodes inside <%= %> and <%- %> output blocks.
(output_directive
  (code) @injection.content
  (#set! injection.language "javascript"))
