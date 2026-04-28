class PwaController < ApplicationController
  def manifest
    render template: "pwa/manifest", formats: [:json], content_type: "application/manifest+json"
  end
end
