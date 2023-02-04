require "../src/texsmart"

puts "Starting NLU engine with worker_count: 4"

engine = Texsmart.new

input = ARGV[0]

out_words = File.open("output/words-2.tsv", "w")
out_phrases = File.open("output/phrases-2.tsv", "w")
out_entities = File.open("output/entities-2.tsv", "w")

line_count = 0

File.each_line(input) do |line|
  line_count += 1
  puts "- Parsing line: #{line_count}" if (line_count % 100 == 0)

  line = line.strip

  words, phrases, entities = engine.parse(line)

  out_words << line << '\n'

  words.each do |word|
    out_words << word.str << '\t' << word.tag << '\t' << word.freq << '\n'
  end

  out_words << '\n'

  out_phrases << line << '\n'

  phrases.each do |phrase|
    out_phrases << phrase.str << '\t' << phrase.tag << '\t' << phrase.freq << '\n'
  end

  out_phrases << '\n'

  out_entities << line << '\n'

  entities.each do |entity|
    out_entities << entity.str << '\t' << entity.idx << '\t' << entity.type << '\n'
  end

  out_entities << '\n'
end

out_words.close
out_phrases.close
out_entities.close
