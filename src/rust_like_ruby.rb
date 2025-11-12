#!/usr/bin/env ruby
# ============================================================
# Rust-like-Ruby — Hybrid Interpreter v1.3 (eval-safe edition)
# ============================================================

class RustLikeRuby
  def initialize
    @env = {}
    @functions = {}
  end

  def run(source)
    lines = source.each_line
    while (line = lines.next rescue nil)
      next if line.strip.empty? || line.strip.start_with?("//")
      execute_line(line.strip, lines)
    end
  end

  def execute_line(line, lines)
    case line
    when /^let\s+(\w+)\s*=\s*(.+);?$/
      @env[$1] = evaluate($2)

    when /^fn\s+(\w+)\s*\(([^)]*)\)\s*\{/
      name, args = $1, $2.split(",").map(&:strip).reject(&:empty?)
      body = extract_block(lines)
      @functions[name] = { args:, body: }

    when /^if\s+(.+)\s*\{/
      cond = evaluate($1)
      block_true = extract_block(lines)
      next_line = safe_peek(lines)
      if next_line&.start_with?("else")
        lines.next
        block_false = extract_block(lines)
      end
      cond ? run(block_true) : run(block_false || "")

    when /^print!\((.+)\);?$/
      puts evaluate($1)

    when /^return\s+(.+);?$/
      throw :return, evaluate($1)

    when /^(\w+)\((.*)\);?$/
      call_function($1, $2)

    else
      evaluate(line) unless line.empty?
    end
  end

  def call_function(name, args_str)
    fn = @functions[name]
    return warn("⚠️ Undefined function: #{name}") unless fn

    args = args_str.split(",").map { |x| evaluate(x.strip) }
    local = @env.clone
    fn[:args].zip(args) { |k, v| local[k] = v }

    result = catch(:return) do
      RustLikeRuby.new.with_env(local).with_functions(@functions).run(fn[:body])
      nil
    end
    result
  end

  # --- safer evaluation (no eval)
  def evaluate(expr)
    return nil if expr.nil? || expr.strip.empty?
    s = expr.dup
    @env.each { |k, v| s.gsub!(/\b#{k}\b/, v.is_a?(String) ? "\"#{v}\"" : v.to_s) }

    # basic operators only
    case s
    when /^"(.+)"\s*\+\s*"(.+)"$/ then $1 + $2
    when /^"(.+)"\s*\+\s*(\d+)$/  then $1 + $2
    when /^(\d+)\s*\+\s*"(.+)"$/  then $1 + $2
    when /^(\d+)\s*\+\s*(\d+)$/   then $1.to_i + $2.to_i
    when /^"(.+)"$/               then $1
    else
      s
    end
  rescue => e
    warn "Eval error: #{e} [expr=#{expr.inspect}]"
    nil
  end

  def with_env(env) = (@env = env; self)
  def with_functions(f) = (@functions = f; self)

  def extract_block(lines)
    blk, depth = "", 1
    while (line = lines.next rescue nil)
      depth += 1 if line.include?("{")
      depth -= 1 if line.include?("}")
      break if depth <= 0
      blk << line
    end
    blk
  end

  def safe_peek(lines)
    loop do
      peek = lines.peek.strip rescue nil
      return nil unless peek
      return peek unless peek.empty? || peek.start_with?("//")
      lines.next
    end
  end
end

if __FILE__ == $0
  f = ARGV[0] or abort("Usage: ruby src/rust_like_ruby.rb <file.rsrb>")
  RustLikeRuby.new.run(File.read(f))
end
