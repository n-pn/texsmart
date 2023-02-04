require "../src/texsmart"

LIMIT   = ENV["LIMIT"]?.try(&.to_i) || 256
WORKERS = ENV["WORKERS"]?.try(&.to_i?) || 4

puts "Starting NLU engine with worker_count: #{WORKERS}"
ENGINE = Texsmart.new(worker_count: WORKERS)

puts "Engine loading completed, parsing!"

INP_DIR = "/app/chivi/var/texts/rgbks"
OUT_DIR = "/mnt/devel/Chivi/analyze"

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

def analyze_file(file : String, out_file = file.sub(INP_DIR, OUT_DIR))
  puts "- Parsing: #{file.sub(INP_DIR, "")}"

  return if File.file?(out_file)

  words_path = out_file.sub(".gbk", "-words.tsv")

  phrases_path = out_file.sub(".gbk", "-phrases.tsv")
  entities_path = out_file.sub(".gbk", "-entities.tsv")

  out_words = File.open(words_path, "w")
  out_phrases = File.open(phrases_path, "w")
  out_entities = File.open(entities_path.sub(".gbk", "-entities.tsv"), "w")

  File.each_line(file, encoding: "GB18030") do |line|
    next if line.empty?
    words, phrases, entities = ENGINE.parse(line)
    write_terms(out_words, words)
    write_terms(out_phrases, phrases)
    write_entities(out_entities, entities)
    out_entities << line << '\n'
  end

  out_words.close
  out_phrases.close
  out_entities.close

  File.touch(out_file)
end

# def analyze_glob(glob : String)
#   glob = File.join(INP_DIR, glob) unless glob.starts_with?(INP_DIR)
#   files = Dir.glob("#{glob}/**/*.gbk")

#   puts "- extract #{glob.sub(INP_DIR, "")}: #{files.size} files"

#   files.map { |x| File.dirname(x) }.uniq!.map { |x| Dir.mkdir_p(x) }
#   files.each { |file| analyze_file(file) }
# end

# ARGV.each do |glob|
#   next if glob.starts_with?('-')
#   analyze_glob(glob)
# end

def analyze_seed(seed : String, limit = 256)
  s_dir = "#{INP_DIR}/#{seed}"
  b_ids = Dir.children(s_dir).map(&.to_i).sort!

  b_ids.each do |s_bid|
    Dir.mkdir_p("#{OUT_DIR}/#{seed}/#{s_bid}")

    files = Dir.glob("#{s_dir}/#{s_bid}/*.gbk")

    if limit > 0
      files.sort_by! { |x| File.basename(x, ".gbk").to_i }
      files = files.first(limit)
    end

    puts "- extract #{seed}/#{s_bid}: #{files.size} files"
    time = Time.measure do
      files.each { |file| analyze_file(file) }
    end

    puts " done in: #{time.total_seconds.round(2)} seconds"
  end
end

ARGV.each do |seed|
  next if seed.starts_with?('-')
  analyze_seed(seed, limit: LIMIT)
end
