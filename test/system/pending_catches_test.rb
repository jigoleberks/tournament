require "application_system_test_case"

# A logged fish must never be destroyable from the device: an unsynced catch is
# the ONLY copy of its photo. On 2026-07-15 a Dismiss tap would have destroyed
# six real photos that turned out to be perfectly intact.
class PendingCatchesTest < ApplicationSystemTestCase
  setup do
    @club = create(:club)
    @user = create(:user, club: @club, name: "Joe")
    @walleye = create(:species, club: @club, name: "Walleye")
  end

  test "a failed catch offers no way to delete it and survives a refresh" do
    seed_failed_catch(uuid: SecureRandom.uuid)

    visit root_path
    assert_selector "[data-pending-catches-target='failedList'] li", wait: 5
    assert_selector "button", text: "Retry"
    assert_no_selector "button", text: "Dismiss"

    visit root_path
    assert_selector "[data-pending-catches-target='failedList'] li", wait: 5,
                    count: 1
  end

  # sync.js stores a human-readable reason on every failure but nothing has ever
  # rendered it, so anglers saw a bare "⚠️ 18″" with no idea what went wrong.
  test "a failed catch shows why it failed" do
    seed_failed_catch(uuid: SecureRandom.uuid,
                      reason: "Photo could not be read from this device")

    visit root_path
    assert_text "Photo could not be read from this device", wait: 5
  end

  test "a failure reason is escaped, not injected as markup" do
    seed_failed_catch(uuid: SecureRandom.uuid, reason: "<img src=x onerror=alert(1)>boom")

    visit root_path
    assert_text "boom", wait: 5
    assert_no_selector "[data-pending-catches-target='failedList'] img"
  end

  private

  def sign_in_as(user)
    SignInToken.issue!(user: user)
    visit consume_session_path(token: SignInToken.last.token)
  end

  def seed_failed_catch(uuid:, reason: "test")
    sign_in_as(@user)
    page.execute_script <<~JS
      window.__seeded = false;
      (async () => {
        const dbReq = indexedDB.open("bsfamilies", 1);
        const db = await new Promise((res, rej) => {
          dbReq.onupgradeneeded = (e) => {
            const d = e.target.result;
            if (!d.objectStoreNames.contains("catches")) {
              const s = d.createObjectStore("catches", { keyPath: "client_uuid" });
              s.createIndex("status", "status");
            }
          };
          dbReq.onsuccess = (e) => res(e.target.result);
          dbReq.onerror   = (e) => rej(e);
        });
        const photo = new Blob([new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0])], { type: "image/jpeg" });
        const tx = db.transaction("catches", "readwrite");
        tx.objectStore("catches").put({
          client_uuid: "#{uuid}",
          species_id: "#{@walleye.id}",
          length_inches: "18",
          length_unit: "inches",
          captured_at_device: new Date().toISOString(),
          photo: photo,
          status: "failed",
          reason: #{reason.to_json},
          queued_at: Date.now()
        });
        await new Promise((res, rej) => { tx.oncomplete = res; tx.onerror = rej; });
        window.__seeded = true;
      })().catch((err) => { window.__seedError = String(err); });
    JS

    Timeout.timeout(5) do
      loop do
        break if page.evaluate_script("window.__seeded === true")
        err = page.evaluate_script("window.__seedError || null")
        flunk "IDB seeding errored: #{err}" if err
        sleep 0.1
      end
    end
  end
end
