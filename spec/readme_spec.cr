require "./spec_helper"

# Joins the README's Crystal blocks into one program, turning each `value # => expected`
# line into a check, so the README examples compile and show true results.
private def readme_program : String
  readme = File.read(Path[__DIR__, "..", "README.md"])
  program = String.build do |io|
    io << <<-'CRYSTAL'
      def readme_check(actual, expected, line : String) : Nil
        return if actual == expected
        STDERR.puts "README: #{line} gave #{actual.inspect}"
        exit 1
      end

      CRYSTAL
    readme.scan(/^```crystal\n(.*?)^```/m) do |match|
      match[1].each_line do |line|
        if check = line.match(/^(\s*)(.+?)\s+# => (.+)$/)
          io << check[1] << "readme_check((" << check[2] << "), (" << check[3] << "), " << line.strip.inspect << ")\n"
        else
          io << line.sub(/^require "cassowary"$/, %(require "./src/cassowary")) << '\n'
        end
      end
    end
  end
  program
end

describe "README" do
  it "shows examples that compile and give the results it claims" do
    output = IO::Memory.new
    status = Process.run(
      "crystal", ["run", "--no-color", "--stdin-filename", "readme_examples.cr"],
      input: IO::Memory.new(readme_program), output: output, error: output,
      chdir: Path[__DIR__, ".."].normalize.to_s,
    )
    fail output.to_s unless status.success?
  end
end
