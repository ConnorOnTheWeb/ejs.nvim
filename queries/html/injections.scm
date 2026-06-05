;; extends

; Inject CSS into <style> elements.
; This ensures CSS highlighting works inside <style> blocks in EJS files
; regardless of whether the active nvim-treesitter HTML injection query
; already provides this -- some installations do not.
((style_element
  (raw_text) @injection.content)
 (#set! injection.language "css"))
