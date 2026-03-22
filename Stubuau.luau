local poke_ast = require("./poke/ast/ast")

local poke = {
	parser = require("./poke/ast/parser"),
	source = require("./poke/ast/source"),
}

local function getText(source: string, span: poke_ast.Span): string
	return string.sub(source, span.x + 1, span.y)
end

local Stubuau = {}

local function baseStub(base: string, stats: {poke_ast.Stat}, cast: string, source: string): string
	local types = ""
	for _, stat in stats do
		if stat.kind == "type" then
			types ..= getText(source, stat.span) .. "\n"
		end
	end
	return base .. types .. "return (nil :: any) :: " .. cast
end

local function getFunctionType(func: poke_ast.Stat_LocalFunction | poke_ast.Stat_Function | poke_ast.Expr_Function, source: string): string
	local body = func.body

	local generics = ""
	if body.generics then
		for _, generic in body.generics.names do
			generics ..= getText(source, generic.span) .. ", "
		end
		generics = generics:sub(1, -3)
		generics = "<" .. generics .. ">"
	end

	local parameters = ""
	for _, param in body.params do
		parameters ..= getText(source, param.name.span) .. ": " .. (if param.type then getText(source, param.type.span) else "any") .. ", "
	end
	parameters = parameters:sub(1, -3)

	local ret = if body.ret then getText(source, body.ret.span) else ""
	if ret == "()" then
		ret = "" -- "-> (())" is invalid type syntax :pensive:
	end

	return `{generics}({parameters}) -> ({ret})`
end

local function metatableType(tbl: string, callMetamethod: poke_ast.Expr_Function, source: string)
	return `typeof(setmetatable(\{} :: {tbl}, \{} :: \{__call: {getFunctionType(callMetamethod, source)}}))`
end

local function moduleStub(base: string, declStat: poke_ast.Stat_LocalVariable, stats: {poke_ast.Stat}, source: string, callMetamethod: poke_ast.Expr_Function?): string
	local decl = declStat.bindings[1]
	local declName = getText(source, decl.name.span)

	if decl.type then
		return baseStub(base, stats, getText(source, decl.type.span), source)
	else
		local properties = ""

		for _, stat in stats do
			if stat.kind == "assign" or stat.kind == "function" then
				local left = if stat.kind == "assign" then stat.left[1].root else stat.names[1]
				local right = if stat.kind == "assign" then stat.right[1] else nil
				if getText(source, left.span) == declName then
					local name do
						local span = if stat.kind == "assign" then stat.left[1].suffixes[#stat.left[1].suffixes].span else stat.names[#stat.names].span
						name = getText(source, span)
						if stat.kind == "assign" then
							name = name:sub(2)
						end
					end
					if stat.kind == "assign" and right then
						local typeCast = if right.kind == "assertion" then getText(source, right.type.span) else "any"
						properties ..= "\n\t" .. name .. ": " .. typeCast .. ","
					elseif stat.kind == "function" then
						properties ..= "\n\t" .. name .. ": " .. getFunctionType(stat, source) .. ","
					end
				end
			end
		end

		if properties == "" then
			print("No properties found for " .. declName)
		end

		properties ..= "\n"
		properties = "{" .. properties .. "}"

		if callMetamethod then
			properties = metatableType(properties, callMetamethod, source)
		end

		return baseStub(base, stats, properties, source)
	end
end

local function functionStub(base: string, stat: poke_ast.Stat_LocalFunction, stats: {poke_ast.Stat}, source: string): string
	return baseStub(base, stats, getFunctionType(stat, source), source)
end

local function assertionStub(base: string, expr: poke_ast.Expr_Assertion, stats: {poke_ast.Stat}, source: string): string
	return baseStub(base, stats, getText(source, expr.type.span), source)
end

local function getCallMetamethod(metaStat: poke_ast.Stat_Call, source: string): poke_ast.Expr_Function?
	local suffix = metaStat.call.suffixes[1]
	assert(suffix.kind == "call", "Invalid suffix for setmetatable")

	local args = suffix.args
	local metatable = args[2]
	assert(metatable and metatable.kind == "table")

	for _, field in metatable.table.fields do
		if field.kind == "namekey" then
			if getText(source, field.name.span) == "__call" then
				assert(field.value.kind == "function", "Invalid __call assignment")
				return field.value
			end
		end
	end

	return nil
end

local function findSetMetatable(declStat: poke_ast.Stat_LocalVariable, stats: {poke_ast.Stat}, source: string): poke_ast.Stat_Call?
	local decl = declStat.bindings[1]
	local declName = getText(source, decl.name.span)

	-- Reverse iteration because currently most API modules use setmetatable towards the end of the script
	for i = #stats, 1, -1 do
		local stat = stats[i]
		if stat.kind ~= "call" then
			continue
		end

		local root = stat.call.root
		if root.kind ~= "name" or getText(source, root.name.span) ~= "setmetatable" then
			continue
		end

		local suffix = stat.call.suffixes[1]
		if suffix.kind ~= "call" then
			continue
		end

		local args = suffix.args
		if getText(source, args[1].span) ~= declName then
			continue
		end

		return stat
	end

	return nil
end

function Stubuau.GenerateStub(base: string, script: string, file: string): string
	local source = poke.source.create(script)
	poke.parser.load(source)

	local block = poke.parser.parse_block()

	local retStat = block.last_stat
	assert(retStat and retStat.kind == "return", "Expected return statement: " .. file)

	local ret = retStat.exprs[1]
	assert(ret, "Expected return value: " .. file)

	if ret.kind == "assertion" then
		return assertionStub(base, ret, block.stats, script)
	end

	assert(ret.kind == "var", "Only variables are supported for return: " .. file)
	assert(ret.var.root.kind == "name", "Only direct variables are supported for return: " .. file)

	local name: string

	if getText(script, ret.var.root.span) == "table" then
		local member = ret.var.suffixes[1]
		if member then
			assert(member.kind == "name" and getText(script, member.span) == ".freeze", "Unsupported table operation: " .. file)

			local call = ret.var.suffixes[2]
			assert(call and call.kind == "call", "Unsupported table operation: " .. file)

			local arg = call.args[1]
			assert(arg and arg.kind == "var", "Unsupported table operation: " .. file)

			name = getText(script, arg.span)
		end
	else
		local span = ret.var.root.span
		name = getText(script, span)
	end

	local declarationStat: poke_ast.Stat_LocalFunction | poke_ast.Stat_LocalVariable?
	for i = #block.stats, 1, -1 do
		local stat = block.stats[i]
		if stat.kind == "localvariable" and getText(script, stat.bindings[1].name.span) == name then
			declarationStat = stat
			break
		elseif stat.kind == "localfunction" and getText(script, stat.name.span) == name then
			declarationStat = stat
			break
		end
	end

	assert(declarationStat, "Could not find declaration: " .. file)

	local stub: string
	if declarationStat.kind == "localvariable" then
		local metatable = findSetMetatable(declarationStat, block.stats, script)
		stub = moduleStub(base, declarationStat, block.stats, script, metatable and getCallMetamethod(metatable, script))
	else
		stub = functionStub(base, declarationStat, block.stats, script)
	end

	return stub
end

return Stubuau