-------------------------------------------------------------------------------
-- Class Test
if Test == nil then
	Test = EternusEngine.BiomeClass.Subclass("Test")
end

-------------------------------------------------------------------------------
function Test:BuildTree()
	--colours
	local red = self:Material("Clay Red")
	local white = self:Material("Clay White")
	local orange = self:Material("Clay Orange")
	local black = self:Material("Clay Black")
	local purple = self:Material("Clay Purple")
	local pink = self:Material("Clay Pink")

	local quickView = true
	
	if quickView then
		local theMaterials = self:SwitchMaterial(black, white, self:Simplex((1 / 16) / 8, 4))

		--terrain
		local theterrain = self:Constant(90)
	
		return theterrain, theMaterials
	else
		local theMaterials = self:SwitchMaterial(red, orange, self:Simplex((1 / 16) / 8, 4))

		--terrain
		local theterrain = self:Constant(90)
	
		return theterrain, theMaterials
	end
end

Test.Lighting =
{
}

Test.Objects =
{
}

Test.Clusters =
{
}

-------------------------------------------------------------------------------
-- Register the Test Generator with the engine.
Eternus.ScriptManager:NKRegisterGeneratorClass(Test)