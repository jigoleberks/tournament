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

  test "magic_link email includes the self-serve code when given" do
    user = create(:user)
    token = SignInToken.issue!(user: user)
    code  = SignInToken.issue_code!(user: user)
    email = SignInMailer.magic_link(token, code: code)
    assert_includes email.body.encoded, code.token
  end

  test "magic_link email without a code still renders" do
    user = create(:user)
    token = SignInToken.issue!(user: user)
    email = SignInMailer.magic_link(token)
    assert_includes email.body.encoded, token.token
  end
end
