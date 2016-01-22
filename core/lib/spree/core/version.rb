module Spree
  def self.version
    ActiveSupport::Deprecation.warn("Spree.version does not work and will be removed from solidus. Use Spree.solidus_version instead to determine the solidus version")
    "2.4.6.beta"
  end

  def self.solidus_version
    "1.3.0.alpha"
  end

  def self.solidus_gem_version
    Gem::Version.new(solidus_version)
  end
end
