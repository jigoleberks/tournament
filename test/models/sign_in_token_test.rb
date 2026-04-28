require "test_helper"

class SignInTokenTest < ActiveSupport::TestCase
  setup { @user = create(:user) }

  test "is created with a uuid token and 30-minute expiry" do
    token = SignInToken.issue!(user: @user)
    assert_match(/\A[0-9a-f-]{36}\z/, token.token)
    assert_in_delta 30.minutes.from_now, token.expires_at, 5
    assert_nil token.used_at
  end

  test "consume! marks the token used and returns the user" do
    token = SignInToken.issue!(user: @user)
    user = SignInToken.consume!(token.token)
    assert_equal @user, user
    assert_not_nil token.reload.used_at
  end

  test "consume! returns nil for an unknown token" do
    assert_nil SignInToken.consume!("nope")
  end

  test "consume! returns nil for an expired token" do
    token = SignInToken.issue!(user: @user)
    token.update!(expires_at: 1.minute.ago)
    assert_nil SignInToken.consume!(token.token)
  end

  test "consume! returns nil for an already-used token" do
    token = SignInToken.issue!(user: @user)
    SignInToken.consume!(token.token)
    assert_nil SignInToken.consume!(token.token)
  end
end
