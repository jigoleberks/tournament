# Pin npm packages by running ./bin/importmap

pin "application"
pin "sw_register", to: "sw_register.js"
pin "offline/sync", to: "offline/sync.js"
pin "offline/db", to: "offline/db.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "idb" # @8.0.3
pin "@hotwired/turbo-rails", to: "turbo.min.js"
