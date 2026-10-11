#!/usr/bin/env ruby
# irx host: Ruby (Onigmo). Ruby's /m is dotall; ^/$ are always line anchors (model gap noted).
require "json"
mode = ARGV[0] || "default"; rep = %w[repeat tierup].include?(mode) ? 2 : 1
$stdout.sync = true
puts "ready ruby-onigmo-#{RUBY_VERSION} mode=#{mode}"
$stdin.each_line do |line|
  next if line.strip.empty?
  # Lone surrogate escapes (valid JSON, rejected by Ruby's parser) become a marker.
  lone = /\\u[dD][89abAB]\h\h(?!\\u[dD][c-fC-F]\h\h)|(?<!\\u[dD][89abAB]\h\h)\\u[dD][c-fC-F]\h\h/
  seq, cases = JSON.parse(line.gsub(lone, "\\uFFFF"))
  out = cases.map do |flags, a, r, pat|
    next(mode == "span" ? "fe400000" : mode == "capture" ? "fe40" + "00" * 26 : "40") if [a, r, pat].any? { |s| s.include?("\uFFFF") }
    opt = (flags.include?("i") ? Regexp::IGNORECASE : 0) | (flags.include?("s") ? Regexp::MULTILINE : 0)
    if mode == "capture" # whole match + groups 1..6 per subject (src/capture.zig)
      begin
        rx = Regexp.new(pat.gsub(/\\x\{([0-9A-Fa-f]+)\}/) { [$1.hex].pack("U") }, opt)
      rescue RegexpError, ArgumentError
        next "fe04" + "00" * 26
      end
      begin
        # With named groups, unnamed ones don't capture: report each named group gN at slot N.
        next [a, r].map { |s|
          m = rx.match(s)
          (0..6).map { |g|
            b = if !m then nil
                elsif rx.names.empty? then (g < m.size ? [m.begin(g), m.end(g)] : nil)
                elsif g == 0 then [m.begin(0), m.end(0)]
                elsif rx.names.include?("g#{g}") then [m.begin("g#{g}"), m.end("g#{g}")]
                end
            b && b[0] ? format("%02x%02x", b[0], b[1]) : "ffff"
          }.join
        }.join
      rescue StandardError
        next "fe08" + "00" * 26
      end
    end
    if mode == "span" # unanchored search, code-point offsets (src/span.zig)
      begin
        rx = Regexp.new(pat.gsub(/\\x\{([0-9A-Fa-f]+)\}/) { [$1.hex].pack("U") }, opt)
      rescue RegexpError, ArgumentError
        next "fe040000"
      end
      begin
        next [a, r].map { |s| (m = rx.match(s)) ? format("%02x%02x", m.begin(0), m.end(0)) : "ffff" }.join
      rescue StandardError
        next "fe080000"
      end
    end
    src = "\\A(?:" + pat.gsub(/\\x\{([0-9A-Fa-f]+)\}/) { [$1.hex].pack("U") } + ")\\z"
    begin
      rx = Regexp.new(src, opt)
    rescue RegexpError, ArgumentError
      next "04"
    end
    bits = 0
    begin
      rep.times { |k| bits |= 1 << (4 * k) if rx.match?(a); bits |= 2 << (4 * k) if rx.match?(r) }
    rescue StandardError
      bits = 8
    end
    format("%02x", bits)
  end
  puts "#{seq} #{out.join}"
end
