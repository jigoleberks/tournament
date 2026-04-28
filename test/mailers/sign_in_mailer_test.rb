require "test_helper"

class SignInMailerTest < ActionMailer::TestCase
  test "magic_link includes the consume URL" do
    user = create(:user, email: "joe@example.com")
    token = SignInToken.issue!(user: user)
    mail = SignInMailer.magic_link(token)

    assert_equal ["joe@example.com"], mail.to
    assert_match token.token, mail.body.encoded
    assert_match "Sign in", mail.subject
  end
end
