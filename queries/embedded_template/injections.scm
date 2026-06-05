;; extends

; Inject HTML into content nodes (text outside <% %> tags).
; injection.combined merges all (content) fragments into a single virtual HTML
; document before parsing. This is required: without it each fragment is parsed
; independently, and fragments that start mid-document (e.g. after a </script>
; tag) cause the HTML parser to enter error recovery immediately, producing
; only ERROR nodes. With combined injection the HTML parser sees a coherent
; document, produces proper element nodes including style_element, and its own
; injection queries fire correctly to inject CSS inside <style> blocks.
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
