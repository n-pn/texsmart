input = "output/entities.tsv"

entities = Hash(String, Hash(String, Int32)).new do |h, k|
  h[k] = Hash(String, Int32).new(0)
end

ignores = {
  "quantity.generic",
  "time.generic",
  "attr.color",
}

File.read(input).split("\n\n").each do |group|
  group.each_line do |line|
    next unless line.includes?('\t')
    word, _offset, type = line.split('\t')
    next unless type.split('.').first.in?("person", "loc", "org")

    entities[word][type] += 1
  end
end

entities = entities.map do |k, v|
  {k, v.to_a.sort_by!(&.[1].-)}
end

entities.sort_by!(&.[1].sum(&.[1]).-)

pp entities
