require "../src/texsmart"

puts "Starting NLU engine with worker_count: 4"

Dir.mkdir_p("out")

NLU = Texsmart.new
input = ARGV[0]

out_words = [] of String
out_entities = [] of String

line_count = 0
char_count = 0

start = Time.monotonic

File.each_line(input) do |line|
  line_count += 1
  puts "- Parsing line: #{line_count} (total #{char_count} chars)" if (line_count % 100 == 0)

  line = line.strip
  next if line.empty?

  char_count += line.size
  words = NLU.parse_no_ner(line)

  words.each do |word|
    out_words << "#{word.str}\t#{word.tag}"
  end
end

tspan = (Time.monotonic - start).total_seconds

puts "time: #{tspan.humanize}"
puts "char_count: #{char_count}"
puts "overall: #{(char_count / tspan).round(3)} chars per second"

File.write("out/words.tsv", out_words.join('\n'))
