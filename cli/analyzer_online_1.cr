require "http/client"
require "json"

require "option_parser"
require "colorize"

API = "https://texsmart.qq.com/api"

TLS = OpenSSL::SSL::Context::Client.insecure

struct JsonData
  include JSON::Serializable

  getter word_list : Array(Term)
  getter phrase_list : Array(Term)
  getter entity_list : Array(Entity)

  struct Term
    include JSON::Serializable

    getter str : String
    getter tag : String
    getter freq : Int32
  end

  struct EntityType
    include JSON::Serializable

    getter name : String
  end

  struct Entity
    include JSON::Serializable

    getter str : String
    getter hit : Tuple(Int32, Int32, Int32, Int32)
    getter tag : String
    getter type : EntityType
    getter meaning : Hash(String, JSON::Any)? = nil
  end
end

struct FullJsonData
  include JSON::Serializable

  getter res_list : Array(JsonData)
end

def call_api(input : Array(String))
  json = {
    str: input,

    options: {
      input_spec:        {lang: "zh"},
      word_seg:          {enable: true},
      pos_tagging:       {enable: true, alg: "CRF"},
      ner:               {enable: true, alg: "fine.high_acc", fine_grained: true},
      syntactic_parsing: {enable: false},
      srl:               {enable: false},
    },
  }

  output = HTTP::Client.post(API, tls: TLS, body: json.to_json, &.body_io.gets_to_end)
  FullJsonData.from_json(output).res_list
end

def write_terms(file : File, terms : Enumerable(JsonData::Term))
  terms.each do |term|
    file << term.str << '\t' << term.tag << '\t' << term.freq << '\n'
  end

  file << '\n'
end

def write_entities(file : File, entities : Enumerable(JsonData::Entity))
  entities.each do |entity|
    file << entity.str << '\t' << entity.hit[0] << '\t' << entity.tag
    file << '\t' << '\t' << entity.meaning.try(&.to_json) << '\n'
  end

  file << '\n'
end

MAX_SIZE  = ENV["MAX"]?.try(&.to_i?) || 5000
DELAY_REQ = ENV["DELAY"]?.try(&.to_i?) || 5

def analyze_file(file : String, encoding = "UTF-8")
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

  lines = [] of String

  line_count = 0
  char_count = 0

  File.each_line(file, encoding: encoding) do |line|
    line_count += 1

    line = line.strip
    next if line.empty?

    lines << line
    char_count += line.size

    next if char_count < MAX_SIZE

    res_list = call_api(lines)
    puts "- Đang phân tích tới dòng thứ #{line_count.colorize.cyan}"

    res_list.each_with_index do |res, idx|
      write_terms(out_words, res.word_list)
      write_terms(out_phrases, res.phrase_list)

      out_entities.puts(lines[idx])
      write_entities(out_entities, res.entity_list)

      res.entity_list.each do |entity|
        entity_type = entity.tag.split('.', 2).first
        next unless entity_type.in?("person", "loc", "org")
        output[entity.str][entity.tag] += 1
      end
    end

    char_count = 0
    lines.clear

    sleep DELAY_REQ.seconds
  end

  out_words.close
  out_phrases.close
  out_entities.close

  output = output.map { |k, v| {k, v, -v.sum(&.[1])} }.sort_by!(&.[2])

  out_file = file.sub(ext, ".output.tsv")
  File.open(out_file, "w") do |file|
    output.each do |k, v, _|
      file << k << '\t'
      v.to_a.sort_by(&.[1].-).join(file, '\t') { |(x, y), io| io << x << ':' << y }
      file << '\n'
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

analyze_file(inp_file, encoding)
