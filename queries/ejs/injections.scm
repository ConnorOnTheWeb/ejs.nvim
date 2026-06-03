;; extends

; Inject HTML into content nodes (text outside <% %> tags)
((content) @injection.content
 (#set! injection.language "html")
 (#set! injection.combined))

; Inject JavaScript into code nodes (text inside <% %> tags)
((code) @injection.content
 (#set! injection.language "javascript")
 (#set! injection.combined))
