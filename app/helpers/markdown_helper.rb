module MarkdownHelper
  SAFE_TAGS = %w[
    p h1 h2 h3 h4 h5 h6 ul ol li strong em a code pre
    blockquote hr br table thead tbody tr th td
  ].freeze
  SAFE_ATTRIBUTES = %w[href].freeze
  DANGEROUS_TAGS = %w[script style iframe object embed].freeze

  def render_markdown(text)
    return "".html_safe if text.blank?
    html = Commonmarker.to_html(
      text,
      options: { render: { unsafe: true }, extension: { autolink: true, strikethrough: true, table: true } }
    )
    doc = Loofah.fragment(html)
    doc.css(*DANGEROUS_TAGS).each(&:remove)
    Rails::Html::SafeListSanitizer.new.sanitize(
      doc.to_s, tags: SAFE_TAGS, attributes: SAFE_ATTRIBUTES
    ).html_safe
  end
end
