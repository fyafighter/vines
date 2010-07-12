module Vines
  class Version
    include Comparable
    attr_accessor :major, :minor

    def initialize(version)
      @major, @minor = version.split('.').map {|i| i.to_i }
    end

    def <=>(version)
      (@major == version.major) ? @minor <=> version.minor : @major <=> version.major
    end

    # rfc 3920bis section 5.4.5
    def negotiate(version)
      default = Version.new('0.9')
      min = [version, self].min
      (min == default) ? nil : min
    end

    def to_s
      "#{@major}.#{@minor}"
    end
  end
end
