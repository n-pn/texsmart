INP_DIR = "/mnt/devel/Chivi/analyze"
OUT_DIR = "/mnt/devel/Chivi/results"

alias Count = Hash(String, Int32)

TERMS = Hash(String, Count).new { |h, k| h[k] = Count.new(0) }

def read_term_file(file : String)
  File.each_line(file) do |line|
    rows = line.split('\t')
    next unless rows.size == 3

    word, ptag = rows
    TERMS[word][ptag] += 1
  end
end

dirs = Dir.children("#{INP_DIR}/!zxcs.me")
dirs.each do |dir|
  inp_dir = "#{INP_DIR}/!zxcs.me/#{dir}"

  files = Dir.glob("#{inp_dir}/*-phrases.tsv")
  puts "#{inp_dir}: #{files.size}"

  files.each do |file|
    read_term_file(file)
  end
end

File.open("#{OUT_DIR}/phrases-freq.tsv", "w") do |file|
  TERMS.each do |word, counts|
    counts.each do |ptag, count|
      file << word << '\t' << ptag << '\t' << count << '\n'
    end
  end
end
