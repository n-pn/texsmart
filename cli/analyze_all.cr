require "colorize"
require "../src/texsmart"

WORKERS = ENV["WORKERS"]?.try(&.to_i?) || 4

puts "Starting NLU engine with worker_count: #{WORKERS}"
ENGINE = Texsmart.new(worker_count: WORKERS)

puts "Engine loading completed, parsing!"

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

def analyze_file(inp_file : String, out_base : String)
  lines = File.read_lines(inp_file, encoding: "GB18030")
  c_len = lines.sum(&.size)

  words_path = "#{out_base}.word_log[M].tsv"
  phrases_path = "#{out_base}.phrase_log[M].tsv"
  entities_path = "#{out_base}.entity_fine[M].tsv"

  inp_base = File.basename(inp_file)

  if info = File.info?(words_path)
    puts "-- #{inp_base} analyzed, skipping!".colorize.blue
    return {c_len, info.modification_time.to_unix}
  else
    puts "-- Parsing: #{inp_base}, words: #{c_len}".colorize.green
  end

  out_words = File.open(words_path, "w")
  out_phrases = File.open(phrases_path, "w")
  out_entities = File.open(entities_path, "w")

  lines.each do |line|
    next if line.empty?
    words, phrases, entities = ENGINE.parse(line)

    write_terms(out_words, words)
    write_terms(out_phrases, phrases)
    write_entities(out_entities, entities)
  end

  out_words.close
  out_phrases.close
  out_entities.close

  {c_len, Time.utc.to_unix}
end

def analyze_book(idx_path : String) : Nil
  out_dir = "#{OUT_DIR}/#{File.basename(idx_path, ".tsv")}"
  Dir.mkdir_p(out_dir)

  input = {} of String => Array(String)

  File.each_line(idx_path) do |line|
    rows = line.split('\t')
    next unless ch_no = rows.first?
    input[ch_no] = rows
  end

  puts "- analyzing #{out_dir}, entries: #{input.size}".colorize.yellow

  start = Time.monotonic

  input.each_value do |rows|
    next if rows.size > 2 # skip analyzed

    ch_no, tpath = rows
    sname = tpath.split('/', 2)[0]

    inp_path = "#{TXT_DIR}/#{tpath}.gbk"
    out_base = "#{out_dir}/#{ch_no}-[#{sname}]"

    c_len, mtime = analyze_file(inp_path, out_base)
    rows << c_len.to_s << mtime.to_s

    File.open(idx_path, "a", &.puts(rows.join('\t')))
  rescue ex
    puts ex.colorize.red
  end

  tdiff = Time.monotonic - start
  puts "Done in: #{tdiff.total_seconds.round(2)} seconds".colorize.cyan
end

INP_DIR = "/app/chivi/var/cvmtl/index"
TXT_DIR = "/app/chivi/var/texts/rgbks"
OUT_DIR = "/app/chivi/var/texts/anlzs"

mod = ENV["MOD"]?.try(&.to_i) || 1
rem = ENV["REM"]?.try(&.to_i) || 0

files = Dir.glob("#{INP_DIR}/*.tsv").map do |file|
  {file, File.basename(file).split('-', 2).first.to_i}
end

files = files.select! { |_, id| id % mod == rem } if mod > 1
files.sort_by!(&.[1])

puts "input: #{files.size}"

files.each do |file, _|
  analyze_book(file)
end
