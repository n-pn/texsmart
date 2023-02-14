INP_DIR = "/mnt/devel/Chivi/analyze"
OUT_DIR = "/mnt/devel/Chivi/results"

def extract_files(inp_paths : Array(String))
  entities = Hash(String, Set({String, String})).new { |h, k| h[k] = Set({String, String}).new }

  inp_paths.each do |inp_path|
    File.each_line(inp_path) do |line|
      rows = line.split('\t')
      next unless rows.size > 4
      key, _idx, tag, _alt, meaning = rows
      entities[tag] << {key, meaning}
    end
  end

  entities.each do |tag, data|
    base_tag = tag.split('.').first
    dir = "#{OUT_DIR}/entities/#{base_tag}"
    Dir.mkdir_p(dir)

    File.open("#{dir}.tsv", "a") do |file|
      data.each { |key, meaning| file << key << '\t' << meaning << '\n' }
    end

    File.open("#{dir}/#{tag}.tsv", "a") do |file|
      data.each { |key, meaning| file << key << '\t' << meaning << '\n' }
    end
  end
end

dirs = Dir.children("#{INP_DIR}/!zxcs.me").sort_by!(&.to_i)

dirs.each do |dir|
  inp_dir = "#{INP_DIR}/!zxcs.me/#{dir}"
  files = Dir.glob("#{inp_dir}/*-entities.tsv")
  puts "#{inp_dir}: #{files.size}"
  extract_files(files)
end

Dir.glob("#{OUT_DIR}/entities/**/*.tsv") do |file_path|
  puts "cleaning: #{file_path}"
  lines = File.read_lines(file_path).uniq!
  File.write(file_path, lines.join('\n'))
end
