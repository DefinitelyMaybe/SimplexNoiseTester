-------------------------------------------------------------------------------
-- Class Test
if Test == nil then
	Test = EternusEngine.BiomeClass.Subclass("Test")
end

-------------------------------------------------------------------------------
function Test:BuildTree()
	--materials
	local theMaterials = self:SwitchMaterial(self:Material("Green Hills"), self:Material("Sand"), self:Simplex((1 / 16) / 1, 1))

	--terrain
	local theterrain = self:Constant(90)

	return theterrain, theMaterials
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