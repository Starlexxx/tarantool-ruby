# frozen_string_literal: true

# Builders for the values crud functions return.
module CrudResponses
  def crud_result(*tuples, fields: %w[id name])
    { 'metadata' => fields.map { |name| { 'name' => name, 'type' => 'any' } }, 'rows' => tuples }
  end

  def crud_error(class_name, message = 'boom', **extra)
    {
      'class_name' => class_name, 'err' => message, 'str' => "#{class_name}: #{message}",
      'file' => 'crud/insert.lua', 'line' => 10
    }.merge(extra.transform_keys(&:to_s))
  end
end
