require "json"
require "colorize"
require "http/client"
require "compress/zip"

require "../src/texsmart"

unless File.exists?("data/common/ca_cert.pem")
  puts "Bạn chưa tải dữ liệu cần thiết cho công cụ!".colorize.red
  exit 1
end

TLS = OpenSSL::SSL::Context::Client.new
TLS.ca_certificates = "data/common/ca_cert.pem"

def fetch_data(url : String)
  HTTP::Client.get(url, tls: TLS) do |res|
    unless res.status.success?
      puts "Có lỗi liên kết tới #{url}".colorize.red
      exit 1
    end

    yield res.body_io
  end
end

# def read_gz(file : String)
#   File.open(file) do |io|
#     Compress::Gzip::Reader.open(io, &.gets_to_end)
#   end
# end

# def save_gz(inp_file : String, data : String)
#   File.open(inp_file, "w") do |io|
#     Compress::Gzip::Writer.open(io, &.print(data))
#   end
# end

print "- ID bộ truyện: "
wn_id = gets.try(&.to_i?) || raise "Sai ID bộ truyện"

print "- Tên nguồn truyện (mặc định: Tổng hợp): "
sname = gets.try(&.strip) || ""
sname = "_" if sname.blank?

seed_url = "https://chivi.app/_wn/seeds/#{wn_id}/#{sname}"

alias SeedData = NamedTuple(curr_seed: NamedTuple(chmax: Int32))

chap_count = fetch_data(seed_url) do |body_io|
  json = SeedData.from_json(body_io)
  json[:curr_seed][:chmax]
end

puts "[#{wn_id}/#{sname}] tổng số chương: #{chap_count.colorize.yellow}"
print "- Phân tích nội dung từ chương 1 tới chương (Enter để chọn tất): "

chap_count = gets.try(&.to_i?) || chap_count

work_dir = "tmp/#{wn_id}(chivi)"
Dir.mkdir_p(work_dir)

print "Đang khởi động công cụ nhận dạng thực thể...".colorize.cyan
ENGINE = Texsmart.new(worker_count: 4)
puts " Hoàn thành!".colorize.cyan

1.upto(chap_count) do |ch_no|
  analyze(work_dir, wn_id, sname, ch_no)
end

puts "- Phân tích hoàn thành, đang tổng hợp kết quả: "

out_zip = "tmp/#{wn_id}_1-#{chap_count}[M].zip"

File.open(out_zip, "w") do |file|
  Compress::Zip::Writer.open(file) do |zip|
    Dir.glob("#{work_dir}/*.tsv") do |path|
      zip.add(File.basename(path), File.open(path))
    end
  end
end

puts "- Kết quả đã được tổng hợp vào tệp tin nén: #{out_zip.colorize.green}"

def analyze(work_dir : String, wn_id : Int32, sname : String, ch_no : Int32)
  out_file = "#{work_dir}/#{ch_no}-[#{sname}].entity_fine[M].tsv"

  if File.file?(out_file)
    puts "- Chương #{ch_no} đã được phân tích!".colorize.blue
    return
  end

  inp_file = "#{work_dir}/#{ch_no}-[#{sname}].txt"
  text_url = "https://chivi.app/_wn/texts/#{wn_id}/#{sname}/#{ch_no}"

  lines = read_inp(inp_file, text_url)

  puts "- Chương #{ch_no.colorize.yellow}: #{lines.first.colorize.yellow}, \
          số dòng: #{lines.size.colorize.yellow}, \
          số ký tự: #{lines.sum(&.size).colorize.yellow}."

  analyze_file(lines, out_file)
end

def analyze_file(lines : Array(String), out_file : String)
  words_io = String::Builder.new
  phrases_io = String::Builder.new
  entities_io = String::Builder.new

  lines.each do |line|
    words, phrases, entities = ENGINE.parse(line)

    serialize_terms(words_io, words)
    serialize_terms(phrases_io, phrases)
    serialize_entities(entities_io, entities)
  end

  File.write(out_file.sub(".entity_fine", ".word_log"), words_io.to_s)
  File.write(out_file.sub(".entity_fine", ".phrase_log"), phrases_io.to_s)
  File.write(out_file, entities_io.to_s)
end

def serialize_terms(io : IO, terms : Enumerable(Texsmart::Term))
  terms.each do |term|
    io << term.str << '\t' << term.tag << '\t' << term.freq << '\n'
  end

  io << '\n'
end

def serialize_entities(io : IO, entities : Enumerable(Texsmart::Entity))
  entities.each do |entity|
    io << entity.str << '\t' << entity.idx << '\t' << entity.type
    io << '\t' << entity.alt_types.join('|')
    io << '\t' << entity.meaning << '\n'
  end

  io << '\n'
end

def read_inp(inp_file : String, text_url : String)
  if File.file?(inp_file)
    data = File.read(inp_file)
  else
    data = fetch_data(text_url) do |body_io|
      NamedTuple(ztext: String).from_json(body_io)[:ztext]
    end

    File.write(inp_file, data)
  end

  data.split(/\R/, remove_empty: true)
end
