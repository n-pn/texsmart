DIR = "/mnt/devel/Chivi/results"

def to_halfwidth(str)
  String.build do |strio|
    str.each_char do |char|
      if (char.ord & 0xff00) == 0xff00
        strio << (char.ord - 0xfee0).chr
      else
        strio << char
      end
    end
  end
end

COMMONS = File.read_lines("#{DIR}/common-initial.txt").to_set

def should_keep?(key, tag, count : Int32)
  return true if COMMONS.includes?(key) # && count >= 5
  return false if tag == "PU"
  count >= 50 && key.matches?(/\p{Han}/)
end

output = {} of String => Set(String)

File.each_line "#{DIR}/words-all.tsv" do |line|
  rows = line.split('\t')
  next unless rows.size == 3

  key, tag, count = rows
  next if key.blank?

  key = to_halfwidth(key)
  next unless should_keep?(key, tag, count.to_i)

  output[key] ||= Set(String).new
  output[key] << rows[1]
end

File.each_line "#{DIR}/phrases-all.tsv" do |line|
  rows = line.split('\t')
  next unless rows.size == 3

  key, tag, count = rows
  next if key.blank?

  key = to_halfwidth(key)
  next unless should_keep?(key, tag, count.to_i)

  output[key] ||= Set(String).new
  output[key] << rows[1]
end

puts "total: #{output.size}"

File.open("#{DIR}/common-terms.tsv", "w") do |file|
  output.each do |key, vals|
    file << key << '\t' << vals.join('\t') << '\n'
  end
end
