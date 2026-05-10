require "test_helper"

class MarkdownHelperTest < ActionView::TestCase
  include MarkdownHelper

  test "renders headings, lists, and links" do
    html = render_markdown("# Title\n\n- one\n- [home](https://example.com)")
    assert_match "<h1>Title</h1>", html
    assert_match "<ul>", html
    assert_match %r{<a href="https://example.com">home</a>}, html
  end

  test "autolinks bare URLs" do
    html = render_markdown("Visit https://example.com today")
    assert_match %r{<a href="https://example.com">https://example.com</a>}, html
  end

  test "renders tables" do
    html = render_markdown("| a | b |\n|---|---|\n| 1 | 2 |\n")
    assert_match "<table>", html
    assert_match "<td>1</td>", html
  end

  test "strips script tags" do
    html = render_markdown("Hello <script>alert(1)</script> world")
    assert_no_match %r{<script}, html
    assert_no_match %r{alert}i, html
  end

  test "strips event-handler attributes" do
    html = render_markdown("<p onclick=\"alert(1)\">click</p>")
    assert_no_match %r{onclick}i, html
  end

  test "strips javascript: URLs from href" do
    html = render_markdown("[bad](javascript:alert(1))")
    assert_no_match %r{javascript:}i, html
  end

  test "returns empty html_safe string for blank input" do
    out = render_markdown("")
    assert_equal "", out
    assert out.html_safe?
  end
end
