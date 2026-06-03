;; extends

; Inject HTML into content nodes (text outside <% %> tags)
((content) @injection.content
 (#set! injection.language "html")
 (#set! injection.combined))

; Inject JavaScript into code nodes inside <% %> scriptlet blocks
((directive (code) @injection.content)
 (#set! injection.language "javascript")
 (#set! injection.combined))

; Inject JavaScript into code nodes inside <%= %> and <%- %> output blocks
((output_directive (code) @injection.content)
 (#set! injection.language "javascript")
 (#set! injection.combined))
