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

	--simplex(scale, numOctaves)
	--The smaller the numerator, the larger the denominators influence.
	-- (1/8)/1  vs (1/64)/1
	-- (1/8)/10 vs (1/64)/10
	--More Octaves = more noise
	local w1 = self:Simplex((1/8)/1, 4)
	local w1 = self:Simplex((1/16)/1, 4)
	----------------------------------------------------------
	--ridge lines
	local ridge_weight1 = self:Simplex((1 / 16) / 8, 4)
	local ridge_weight2 = self:Simplex((1 / 32) / 8, 6)

	--Mountains
	local mt_weight1 = self:Simplex((1 / 64) / 8, 6)
	local mt_weight2 = self:Simplex((1 / 64) / 12, 12)
	local mt_weight3 = self:Simplex((1 / 128) / 5, 8)
	----------------------------------------------------------

	if quickView then
		local theMaterials = self:SwitchMaterial(black, white, w1)

		--terrain
		local theterrain = self:Constant(90)
	
		return theterrain, theMaterials
	else
		local theMaterials = self:SwitchMaterial(red, orange, self:Simplex((1 / 128) / 5, 8))

		--terrain
		local theterrain = self:Multiply(self:Simplex((1 / 128) / 5, 8), self:Constant(140))

		theterrain = self:Max(theterrain, self:Constant(140))
	
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