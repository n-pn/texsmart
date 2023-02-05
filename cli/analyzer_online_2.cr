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

class Analyzer
  def initialize(@pos_alg : String, @ner_alg : String, @max_chars = 5000, @req_delay = 5)
    puts "- Thuật toán tách từ: #{pos_alg.colorize.yellow}"
    puts "- Thuật toán nhận dạng: #{ner_alg.colorize.yellow}"

    puts "- Số ký tự tối đa gửi api: #{max_chars.colorize.yellow} từ/lượt gửi"
    puts "- Giới hạn lượt gọi api: #{req_delay.colorize.yellow} giây/lượt gửi"

    @tls = OpenSSL::SSL::Context::Client.new

    {% if flag?(:win32) %}
      ca_file = "C:/Program Files/Common Files/SSL/cacert.pem"
      download_cacert(ca_file) unless File.file?(ca_file)
      @tls.ca_certificates = ca_file
    {% end %}
  end

  private def download_cacert(out_file : String)
    url = "https://curl.se/ca/cacert-2023-01-10.pem"
    tls = OpenSSL::SSL::Context::Client.insecure

    HTTP::Client.get(url, tls: tls) do |res|
      Dir.mkdir_p(File.dirname(out_file))
      File.write(out_file, res.body_io)
    end

    raise "Không tải được file cacert, hãy liên hệ ban quản trị" unless File.file?(out_file)
  end

  API = "https://texsmart.qq.com/api"

  def call_api(input : Array(String), delay = 1)
    json = {
      str: input,

      options: {
        input_spec:        {lang: "zh"},
        word_seg:          {enable: true},
        pos_tagging:       {enable: true, alg: @pos_alg},
        ner:               {enable: true, alg: @ner_alg, fine_grained: true},
        syntactic_parsing: {enable: false},
        srl:               {enable: false},
      },
    }

    HTTP::Client.post(API, tls: @tls, body: json.to_json) do |res|
      body = res.body_io.gets_to_end

      if !res.status.success? || body.empty?
        raise body.empty? ? "API không trả về kết quả" : body
      end

      FullJsonData.from_json(body).res_list
    end
  rescue ex
    puts "Lỗi gọi API: #{ex.message}, chương trình sẽ tự động thử lại sau #{delay * 10} giây".colorize.red
    sleep delay * 10
    call_api(input, delay * 2)
  end

  private def write_terms(file : File, terms : Enumerable(JsonData::Term))
    terms.each do |term|
      file << term.str << '\t' << term.tag << '\t' << term.freq << '\n'
    end

    file << '\n'
  end

  private def write_entities(file : File, entities : Enumerable(JsonData::Entity))
    entities.each do |entity|
      file << entity.str << '\t' << entity.hit[0] << '\t' << entity.tag
      file << '\t' << '\t' << entity.meaning.try(&.to_json) << '\n'
    end

    file << '\n'
  end

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

    out_path = path.sub(".txt", ".output.tsv")
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

      next if char_count < @max_chars

      part_count += 1

      res_path = File.join(out_dir, "#{part_count}.output.tsv")
      next if File.file?(res_path)

      out_path = File.join(out_dir, "#{part_count}.txt")
      analyze_part(part_lines, out_path, "#{line_count}/#{lines.size}")

      part_lines.clear
      char_count = 0

      sleep @req_delay
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
end

inp_file = ""
encoding = "UTF-8"

pos_alg = "CRF"
ner_alg = "fine.high_acc"

max_chars = ENV["MAX"]?.try(&.to_i?) || 5000
req_delay = ENV["DELAY"]?.try(&.to_i?) || 5

OptionParser.parse(ARGV) do |parser|
  parser.banner = "Cách dùng: analyzer_online_2.1.exe [...]"

  parser.on("-i FILE", "Tệp dữ liệu đầu vào") { |i| inp_file = i }
  parser.on("-e ENCODING", "Biên mã ký tự") { |e| encoding = e }

  parser.on("--pos-alg POS_ALG", "Giải thuật phân tách cụm từ") { |s| pos_alg = s }
  parser.on("--ner-alg NER_ALG", "Giải thuật nhận dạng thực tể") { |s| ner_alg = s }

  parser.on("--max-chars MAX_CHARS", "Số từ gửi đi mỗi lượt gọi api") { |i| max_chars = i.to_i }
  parser.on("--req-delay REQ_DELAY", "Giới hạn số lượt gọi api") { |i| req_delay = i.to_i }

  parser.on("-h", "--help", "Hiển thị các lựa chọn") do
    puts parser
    exit
  end
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

max_chars = 7500 if max_chars > 7500
req_delay = 0 if req_delay < 0

analyzer = Analyzer.new(pos_alg, ner_alg, max_chars: max_chars, req_delay: req_delay)
analyzer.analyze_file(inp_file, encoding)
