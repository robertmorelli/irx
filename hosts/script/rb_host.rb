#!/usr/bin/env ruby
# irx host: Ruby (Onigmo). Ruby's /m is dotall; ^/$ are always line anchors (model gap noted).
require "json"
mode = ARGV[0] || "default"; rep = %w[repeat tierup].include?(mode) ? 2 : 1
# Long modes (lspan, lcapture): 4 hex digits per position, ffff = none, fffe + 00bb = failed.
WIDE = %w[lspan lcapture].include?(mode)
D = WIDE ? 4 : 2
NONE = "f" * (2 * D)
def pair(s, e) = format("%0#{D}x%0#{D}x", s, e)
def failed(b, rest) = (WIDE ? format("fffe%04x", b) : format("fe%02x", b)) + "0" * (D * rest)
sticky = mode == "aspan"  # the match must start at the offset: \G(?:p) with match(s, pos)
is_span = %w[span lspan ospan aspan].include?(mode); is_cap = %w[capture lcapture].include?(mode)
$stdout.sync = true
puts "ready ruby-onigmo-#{RUBY_VERSION} mode=#{mode}"
$stdin.each_line do |line|
  next if line.strip.empty?
  # Lone surrogate escapes (valid JSON, rejected by Ruby's parser) become a marker.
  lone = /\\u[dD][89abAB]\h\h(?!\\u[dD][c-fC-F]\h\h)|(?<!\\u[dD][89abAB]\h\h)\\u[dD][c-fC-F]\h\h/
  seq, cases = JSON.parse(line.gsub(lone, "\\uFFFF"))
  out = cases.map do |flags, a, r, pat|
    if mode == "bench" # Shootout 2: "<flags>#<reps>"; compile once, time match? searches
      flags, n = flags.split("#", 2); n = [(n || "1").to_i, 1].max; flags ||= ""
      next("fe40" + "0" * 36) if [a, r, pat].any? { |s| s.include?("\uFFFF") }
      opt = (flags.include?("i") ? Regexp::IGNORECASE : 0) | (flags.include?("s") ? Regexp::MULTILINE : 0)
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      rx = (Regexp.new(pat.gsub(/\\x\{([0-9A-Fa-f]+)\}/) { "\\u{#{$1}}" }, opt) rescue nil)
      next("fe04" + "0" * 36) unless rx
      tc = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - t0
      begin
        bits = (rx.match?(a) ? 1 : 0) | (rx.match?(r) ? 2 : 0)
        t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        n.times { rx.match?(a) }
        t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        n.times { rx.match?(r) }
        t3 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      rescue StandardError
        next("fe08" + "0" * 36)
      end
      next(format("%02x%012x%012x%012x", bits, tc, t2 - t1, t3 - t2))
    end
    # ospan: "<flags>@<a>,<r>" = search start per subject (characters)
    starts = [0, 0]
    flags, offs = flags.split("@", 2)
    flags ||= ""
    starts = offs.split(",").map(&:to_i) if offs
    next(is_span ? failed(0x40, 2) : is_cap ? failed(0x40, 26) : "40") if [a, r, pat].any? { |s| s.include?("\uFFFF") }
    opt = (flags.include?("i") ? Regexp::IGNORECASE : 0) | (flags.include?("s") ? Regexp::MULTILINE : 0)
    if is_cap # whole match + groups 1..6 per subject (src/capture.zig)
      begin
        rx = Regexp.new(pat.gsub(/\\x\{([0-9A-Fa-f]+)\}/) { "\\u{#{$1}}" }, opt)
      rescue RegexpError, ArgumentError
        next failed(4, 26)
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
            b && b[0] ? pair(b[0], b[1]) : NONE
          }.join
        }.join
      rescue StandardError
        next failed(8, 26)
      end
    end
    if is_span # unanchored search, code-point offsets (src/span.zig)
      begin
        src = pat.gsub(/\\x\{([0-9A-Fa-f]+)\}/) { "\\u{#{$1}}" }
        rx = Regexp.new(sticky ? "\\G(?:#{src})" : src, opt)
      rescue RegexpError, ArgumentError
        next failed(4, 2)
      end
      begin
        next [[a, starts[0]], [r, starts[1]]].map { |s, k| (m = rx.match(s, k)) ? pair(m.begin(0), m.end(0)) : NONE }.join
      rescue StandardError
        next failed(8, 2)
      end
    end
    src = "\\A(?:" + pat.gsub(/\\x\{([0-9A-Fa-f]+)\}/) { "\\u{#{$1}}" } + ")\\z"
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
