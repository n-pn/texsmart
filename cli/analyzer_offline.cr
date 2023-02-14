require "option_parser"
require "colorize"

require "../src/texsmart"

WORKERS = ENV["WORKERS"]?.try(&.to_i?) || 4

def write_terms(file : File, terms : Enumerable(Texsmart::Term))
  terms.each do |term|
    file << term.str << '\t' << term.tag << '\t' << term.freq << '\n'
  end

  file << '\n'
end

def write_entities(file : File, entities : Enumerable(Texsmart::Entity))
  entities.each do |entity|
    file << entity.str << '\t' << entity.idx << '\t' << entity.type
    file << '\t' << entity.alt_types.join('|')
    file << '\t' << entity.meaning << '\n'
  end

  file << '\n'
end

def analyze_file(engine, file : String, encoding = "UTF-8")
  puts "- Tệp đầu vào: #{file.colorize.yellow}, biên mã ký tự: #{encoding.colorize.yellow}"

  ext = File.extname(file)

  words_path = file.sub(ext, ".words.tsv")
  phrases_path = file.sub(ext, ".phrases.tsv")
  entities_path = file.sub(ext, ".entities.tsv")

  out_words = File.open(words_path, "w")
  out_phrases = File.open(phrases_path, "w")
  out_entities = File.open(entities_path, "w")

  output = Hash(String, Hash(String, Int32)).new do |h, k|
    h[k] = Hash(String, Int32).new(0)
  end

  line_count = 0
  File.each_line(file, encoding: encoding) do |line|
    line_count += 1

    if line_count % 10 == 0
      puts "- Đang phân tích tới dòng thứ #{line_count.colorize.cyan}"
    end

    line = line.strip
    next if line.empty?

    words, phrases, entities = engine.parse(line)
    write_terms(out_words, words)
    write_terms(out_phrases, phrases)
    write_entities(out_entities, entities)

    entities.each do |entity|
      entity_type = entity.type.split('.', 2).first
      next unless entity_type.in?("person", "loc", "org")
      output[entity.str][entity.type] += 1
    end
  end

  out_words.close
  out_phrases.close
  out_entities.close

  output = output.map { |k, v| {k, v, -v.sum(&.[1])} }.sort_by!(&.[2])

  out_file = file.sub(ext, ".output.tsv")
  File.open(out_file, "w") do |fileio|
    output.each do |k, v, _|
      fileio << k << '\t'
      v.to_a.sort_by(&.[1].-).join(fileio, '\t') { |(x, y), io| io << x << ':' << y }
      fileio << '\n'
    end
  end

  puts "-Phân tích dữ liệu hoàn thành, tệp kết quả: #{out_file.colorize.green}"
end

inp_file = ""
encoding = "UTF-8"

OptionParser.parse(ARGV) do |parser|
  parser.banner = "Cách dùng: analyzer.exe [...]"

  parser.on("-i FILE", "Tệp dữ liệu đầu vào") { |i| inp_file = i }
  parser.on("-e ENCODING", "Biên mã ký tự") { |e| encoding = e }
end

if inp_file.empty?
  print "Nhập tệp đầu vào: ".colorize.cyan
  inp_file = gets.not_nil!.strip

  print "Biên mã ký tự (1: UTF-8, 2: GB18030, 3: UTF-16): ".colorize.cyan
  case input = gets.try(&.strip) || ""
  when "1" then encoding = "UTF-8"
  when "2" then encoding = "GB18030"
  when "3" then encoding = "UTF-16"
  else          encoding = input unless input.empty?
  end
end

print "Khởi động công cụ AI... ".colorize.cyan
engine = Texsmart.new(worker_count: WORKERS)
puts "Công cụ đã khởi động xong, sẵn sàn phân tích dữ liệu!".colorize.cyan

analyze_file(engine, inp_file, encoding)
