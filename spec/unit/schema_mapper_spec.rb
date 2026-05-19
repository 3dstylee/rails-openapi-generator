# frozen_string_literal: true

RSpec.describe RailsOpenapiGenerator::SchemaMapper do
  subject(:mapper) { described_class.new }

  def param(type:, constraints: {})
    RailsOpenapiGenerator::ParamCall.new(
      name: "p", type: type, required: false, constraints: constraints, fully_resolved: true
    )
  end

  describe "type mapping" do
    {
      "String" => { "type" => "string" },
      "Integer" => { "type" => "integer" },
      "Float" => { "type" => "number" },
      "Boolean" => { "type" => "boolean" },
      "Array" => { "type" => "array" },
      "Hash" => { "type" => "object" },
      "Date" => { "type" => "string", "format" => "date" },
      "DateTime" => { "type" => "string", "format" => "date-time" }
    }.each do |type, schema|
      it "maps #{type} to #{schema}" do
        expect(mapper.map(param(type: type))).to eq(schema)
      end
    end

    it "falls back to string for an unknown type" do
      expect(mapper.map(param(type: "SomethingElse"))).to eq("type" => "string")
    end
  end

  describe "constraint mapping" do
    it "maps an :in list to enum" do
      schema = mapper.map(param(type: "String", constraints: { in: %w[admin member] }))
      expect(schema["enum"]).to eq(%w[admin member])
    end

    it "maps an inclusive :in range to minimum/maximum" do
      schema = mapper.map(param(type: "Integer", constraints: { in: 1..100 }))
      expect(schema).to include("minimum" => 1, "maximum" => 100)
    end

    it "maps an exclusive :in range to exclusiveMaximum" do
      schema = mapper.map(param(type: "Integer", constraints: { in: 1...100 }))
      expect(schema).to include("minimum" => 1, "exclusiveMaximum" => 100)
    end

    it "maps :min and :max" do
      schema = mapper.map(param(type: "Integer", constraints: { min: 5, max: 9 }))
      expect(schema).to include("minimum" => 5, "maximum" => 9)
    end

    it "maps :min_length and :max_length" do
      schema = mapper.map(param(type: "String", constraints: { min_length: 2, max_length: 8 }))
      expect(schema).to include("minLength" => 2, "maxLength" => 8)
    end

    it "maps a string :format to pattern" do
      schema = mapper.map(param(type: "String", constraints: { format: ".+@.+" }))
      expect(schema["pattern"]).to eq(".+@.+")
    end

    it "maps blank: false on a string to minLength 1" do
      schema = mapper.map(param(type: "String", constraints: { blank: false }))
      expect(schema["minLength"]).to eq(1)
    end
  end
end
