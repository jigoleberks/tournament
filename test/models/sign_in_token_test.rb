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

  test "consume! refuses to accept code-kind tokens" do
    code = SignInToken.issue_code!(user: @user)
    assert_nil SignInToken.consume!(code.token)
  end

  test "issue_code! creates an 8-digit code valid 10 minutes" do
    code = SignInToken.issue_code!(user: @user)
    assert_match(/\A\d{8}\z/, code.token)
    assert_equal "code", code.kind
    assert_in_delta 10.minutes.from_now, code.expires_at, 5
  end

  test "issue_code! invalidates any prior open code for the user" do
    first = SignInToken.issue_code!(user: @user)
    SignInToken.issue_code!(user: @user)
    assert_not_nil first.reload.used_at
  end

  test "consume_code! signs in when email and code match" do
    code = SignInToken.issue_code!(user: @user)
    assert_equal @user, SignInToken.consume_code!(email: @user.email, code: code.token)
    assert_not_nil code.reload.used_at
  end

  test "consume_code! returns nil on email mismatch" do
    code = SignInToken.issue_code!(user: @user)
    assert_nil SignInToken.consume_code!(email: "wrong@example.com", code: code.token)
    assert_nil code.reload.used_at
  end

  test "consume_code! locks the code after MAX_ATTEMPTS wrong tries" do
    code = SignInToken.issue_code!(user: @user)
    SignInToken::CODE_MAX_ATTEMPTS.times do
      assert_nil SignInToken.consume_code!(email: @user.email, code: "00000000")
    end
    assert_not_nil code.reload.used_at
    assert_nil SignInToken.consume_code!(email: @user.email, code: code.token)
  end

  test "consume_code! is nil when no open code exists" do
    assert_nil SignInToken.consume_code!(email: @user.email, code: "12345678")
  end

  test "consume! returns nil for a deactivated user" do
    token = SignInToken.issue!(user: @user)
    @user.update!(deactivated_at: Time.current)
    assert_nil SignInToken.consume!(token.token)
    assert_nil token.reload.used_at
  end

  test "consume_code! returns nil for a deactivated user" do
    code = SignInToken.issue_code!(user: @user)
    @user.update!(deactivated_at: Time.current)
    assert_nil SignInToken.consume_code!(email: @user.email, code: code.token)
    assert_nil code.reload.used_at
  end

  # Simulates a TOCTOU race against consume!: in-memory used_at is still nil,
  # but the DB row was claimed by a parallel request between find_by and the
  # atomic update. The WHERE used_at IS NULL guard makes the second call miss.
  test "consume! does not double-consume when the row is claimed mid-flight" do
    token = SignInToken.issue!(user: @user)
    SignInToken.where(id: token.id).update_all(used_at: 1.second.ago)
    assert_nil SignInToken.consume!(token.token)
  end

  # Direct test of the atomic primitive. consume_code!'s race window opens
  # after .open.first returns a record, and a single-threaded test can't
  # easily reproduce that — but if the primitive is atomic, the race is closed.
  test "claim only succeeds once for the same row" do
    code = SignInToken.issue_code!(user: @user)
    assert SignInToken.send(:claim, code), "first claim should win"
    assert_not SignInToken.send(:claim, code), "second claim should miss"
  end
end
