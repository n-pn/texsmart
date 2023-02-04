require "http/client"
require "json"

require "option_parser"
require "colorize"

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

API = "https://texsmart.qq.com/api"
TLS = OpenSSL::SSL::Context::Client.insecure

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

  output = HTTP::Client.post(API, tls: TLS, body: json.to_json) do |res|
    body = res.body_io.gets_to_end
    break body if res.status.success?

    puts body.colorize.red
    exit 1
  end

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

alias OutData = Hash(String, Hash(String, Int32))

def save_output(path : String, data : OutData)
  data = data.map { |k, v| {k, v, -v.sum(&.[1])} }.sort_by!(&.[2])
  File.open(path, "w") do |io|
    data.each do |k, v, _|
      io << k << '\t'
      v.to_a.sort_by(&.[1].-).join(io, '\t') { |(x, y), z| z << x << ':' << y }
      io << '\n'
    end
  end
end

def analyze_part(lines : Array(String), path : String, label = "-/-")
  puts "- <#{label}> tệp #{path.colorize.cyan}, số dòng: #{lines.size.colorize.cyan}"

  out_path = path.sub(".txt", ".output.tsv")
  return if File.file?(out_path)

  File.write(path, lines.join("\n"))

  word_lists = [] of Array(JsonData::Term)
  phrase_lists = [] of Array(JsonData::Term)
  entity_lists = [] of Array(JsonData::Entity)

  out_data = OutData.new do |h, k|
    h[k] = Hash(String, Int32).new(0)
  end

  call_api(lines).each_with_index do |res, idx|
    word_lists << res.word_list
    phrase_lists << res.phrase_list
    entity_lists << res.entity_list

    res.entity_list.each do |entity|
      entity_type = entity.tag.split('.', 2).first
      next unless entity_type.in?("person", "loc", "org")
      out_data[entity.str][entity.tag] += 1
    end
  end

  File.open(path.sub(".txt", ".words.tsv"), "w") do |file|
    word_lists.each { |list| write_terms(file, list) }
  end

  File.open(path.sub(".txt", ".phrases.tsv"), "w") do |file|
    phrase_lists.each { |list| write_terms(file, list) }
  end

  File.open(path.sub(".txt", ".entities.tsv"), "w") do |file|
    entity_lists.each { |list| write_entities(file, list) }
  end

  save_output(out_path, out_data)
end

def analyze_file(file : String, encoding = "UTF-8")
  puts "- Tệp đầu vào: #{file.colorize.yellow}, biên mã ký tự: #{encoding.colorize.yellow}"

  ext = File.extname(file)

  out_dir = file.sub(ext, "")
  Dir.mkdir_p(out_dir)

  part_count = 0
  char_count = 0
  line_count = 0

  part_lines = [] of String

  lines = File.read_lines(file, encoding: encoding)

  lines.each do |line|
    line_count += 1

    line = line.strip
    next if line.empty?

    part_lines << line
    char_count += line.size

    next if char_count < MAX_SIZE

    part_count += 1

    out_path = File.join(out_dir, "#{part_count}.txt")
    analyze_part(part_lines, out_path, "#{line_count}/#{lines.size}")

    part_lines.clear
    char_count = 0

    sleep DELAY_REQ
  end

  File.open(file.sub(ext, ".words.tsv"), "w") do |file|
    part_count.times do |part|
      file.puts if part > 0
      file.puts File.read(File.join(out_dir, "#{part + 1}.words.tsv"))
    end
  end

  File.open(file.sub(ext, ".phrases.tsv"), "w") do |file|
    part_count.times do |part|
      file.puts if part > 0
      file.puts File.read(File.join(out_dir, "#{part + 1}.phrases.tsv"))
    end
  end

  File.open(file.sub(ext, ".entities.tsv"), "w") do |file|
    part_count.times do |part|
      file.puts if part > 0
      file.puts File.read(File.join(out_dir, "#{part + 1}.entities.tsv"))
    end
  end

  out_data = OutData.new do |h, k|
    h[k] = Hash(String, Int32).new(0)
  end

  part_count.times do |part|
    File.each_line(File.join(out_dir, "#{part + 1}.output.tsv")) do |line|
      cols = line.split('\t')
      next unless word = cols.shift?

      cols.each do |col|
        tag, count = col.split(':', 2)
        out_data[word][tag] += count.to_i
      end
    end
  end

  out_path = file.sub(ext, ".output.tsv")
  save_output(out_path, out_data)

  puts "-Phân tích dữ liệu hoàn thành, tệp kết quả: #{out_path.colorize.green}"
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
