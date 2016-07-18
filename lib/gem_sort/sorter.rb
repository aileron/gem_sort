module GemSort
  class Sorter
    def extract_blocks!(lines, begin_block_condition, nested = false)
      end_block_condition = lambda do |line|
        (nested ? line.strip : line).start_with?('end')
      end
      blocks = []

      until lines.select(&begin_block_condition).empty?
        begin_block_index = lines.index(&begin_block_condition)
        block_length = lines
                       .slice(begin_block_index..lines.length)
                       .index(&end_block_condition)
        block_length += 1
        blocks << lines.slice!(begin_block_index, block_length)
      end
      blocks
    end

    def extract_line!(lines, condition)
      target_line = lines.select(&condition).first
      lines.delete_if { |line| line == target_line } unless target_line.nil?
      target_line
    end

    def sort_block_gems(block)
      wrap_block(block, unwrap_block(block).sort)
    end

    def wrap_block(block, inside)
      [
        block.first,
        *inside,
        block.last
      ]
    end

    def unwrap_block(block)
      block[1..block.length - 2]
    end

    def inject_between(array, divider)
      array.each_with_index.inject([]) do |acc, (item, _i)|
        acc << item
        acc << divider if array.last != item
        acc
      end
    end

    def source_gemfile
      ::Rails.root.join('Gemfile').open('r+')
    end

    def read_gemfile
      source_gemfile.read.split("\n").select { |line| line != '' }
    end

    def write_gemfile(text)
      source_gemfile.write(text)
    end

    def sort!
      gemfile = read_gemfile

      group_blocks = extract_blocks!(gemfile, lambda do |line|
        line.start_with?('group')
      end).map do |group_block|
        sort_block_gems(group_block)
      end

      source_blocks = extract_blocks!(gemfile, lambda  do |line|
        line.start_with?('source ') && line.end_with?('do')
      end).map do |source_block|
        source_inside = unwrap_block(source_block)
        inside_group_blocks = extract_blocks!(source_inside, lambda do |line|
          line.strip.start_with?('group')
        end, true).map do |inside_group_block|
          sort_block_gems(inside_group_block)
        end
        inside = source_inside.sort + inject_between(inside_group_blocks, nil)
        wrap_block(source_block, inside)
      end

      source_line = extract_line!(gemfile, lambda do |line|
        line.start_with?('source') && !line.end_with?('do')
      end)

      ruby_line = extract_line!(gemfile, lambda do |line|
        line.start_with?('ruby')
      end)

      rails_line = extract_line!(gemfile, lambda do |line|
        line.start_with?('gem "rails"') || line.start_with?("gem 'rails'")
      end)

      sorted_text = inject_between([
                                     source_line,
                                     [ruby_line, rails_line],
                                     gemfile.sort,
                                     inject_between(group_blocks, nil),
                                     inject_between(source_blocks, nil)
                                   ], nil).flatten.join("\n")

      write_gemfile(sorted_text)
    end
  end
end
