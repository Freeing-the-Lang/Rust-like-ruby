#!/usr/bin/env ruby
# ============================================================
# Rust-like-Ruby — Hybrid Interpreter Prototype v1.2
# Author: 0200134
# License: MIT
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

  # ---------------- Core Execution ----------------
  def execute_line(line, lines)
    case line
    when /^let\s+(\w+)\s*=\s*(.+);?$/
      name, value = $1, eval_expr($2)
      @env[name] = value

    when /^fn\s+(\w+)\s*\(([^)]*)\)\s*\{/
      name, args = $1, $2.split(",").map(&:strip).reject(&:empty?)
      body = extract_block(lines)
      @functions[name] = { args:, body: }

    when /^if\s+(.+)\s*\{/
      cond = eval_expr($1)
      block_true = extract_block(lines)

      # safely peek next meaningful line
      next_line = nil
      loop do
        peek = lines.peek.strip rescue nil
        break unless peek
        if peek.empty? || peek.start_with?("//")
          lines.next
          next
        end
        next_line = peek
        break
      end

      if next_line&.start_with?("else")
        lines.next
        block_false = extract_block(lines)
      else
        block_false = nil
      end

      if cond
        run(block_true)
      elsif block_false
        run(block_false)
      end

    when /^print!\((.+)\);?$/
      puts eval_expr($1)

    when /^return\s+(.+);?$/
      throw :return, eval_expr($1)

    when /^(\w+)\((.*)\);?$/
      call_function($1, $2)

    else
      eval_expr(line) unless line.empty?
    end
  end

  # ---------------- Function Call ----------------
  def call_function(name, arglist)
    fn = @functions[name]
    unless fn
      warn "⚠️ Undefined function: #{name}"
      return
    end

    args_values = arglist.split(",").map { |a| eval_expr(a.strip) }
    local = @env.clone
    fn[:args].zip(args_values) { |k, v| local[k] = v }

    result = catch(:return) do
      RustLikeRuby.new.with_env(local).with_functions(@functions).run(fn[:body])
      nil
    end
    result
  end

  # ---------------- Safe Expression Eval ----------------
  def eval_expr(expr)
    return nil if expr.nil? || expr.strip.empty?

    expr = expr.gsub(/\b(\w+)\b/) do
      if @env.key?($1)
        val = @env[$1]
        val.is_a?(String) ? "\"#{val}\"" : val.to_s
      else
        $1
      end
    end

    eval(expr)
  rescue SyntaxError
    # swallow invalid partial syntax (e.g., isolated "else")
    nil
  rescue => e
    warn "Eval error: #{e} [expr=#{expr.inspect}]"
    nil
  end

  def with_env(env)
    @env = env
    self
  end

  def with_functions(funcs)
    @functions = funcs
    self
  end

  # ---------------- Block Extractor ----------------
  def extract_block(lines)
    block = ""
    depth = 1
    while (line = lines.next rescue nil)
      depth += 1 if line.include?("{")
      depth -= 1 if line.include?("}")
      break if depth <= 0
      block << line
    end
    block
  end
end

# ---------------- CLI Runner ----------------
if __FILE__ == $0
  path = ARGV[0] or abort("Usage: ruby src/rust_like_ruby.rb <file.rsrb>")
  source = File.read(path)
  RustLikeRuby.new.run(source)
end
