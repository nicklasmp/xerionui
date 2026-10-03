local addonName, XerionUIFeatures = ...

-- Live previews of a module's own frame, shown at the top of its config page.
--
-- Host-neutral core. The preview is a second instance built by the module's own
-- GenerateFrame, so it styles itself exactly like the live one -- no duplicated
-- drawing code anywhere. Each host supplies a `display` frame to hang it in:
--
--   integrations/ace/preview.lua       -- the "ItruliaPreview" AceGUI widget
--   integrations/ellesmere/ellesmere.lua -- EllesmereUI's content header
--
-- A module opts in by defining Module:PreparePreview(frame), which puts the
-- instance into the state its OnEvent would reach when the feature fires (text
-- shown, sample values filled in). Modules that draw nothing simply omit it and
-- get no preview.

-- Where preview frames live while nothing is showing them. WoW frames can never be
-- destroyed, so parking -- hidden and out of the config window's frame tree -- is as
-- close to freeing as the API allows.
local previewPool = CreateFrame("frame")
previewPool:Hide()

-- module -> the display frame currently hosting its preview. Nil for every module
-- whose page is not open, which is what makes RefreshPreview a cheap no-op.
XerionUIFeatures.activePreviews = {}

-- Builds the module's preview instance once and caches it on the module.
--
-- pcall'd because GenerateFrame may reach for data the character does not have (the
-- flying bar reads Vigor's charge count, for example); a module that cannot build a
-- preview shows an empty box rather than erroring out the whole page.
function XerionUIFeatures:EnsurePreviewFrame(module)
    if module.previewFrame then
        return module.previewFrame
    end

    if not module.GenerateFrame then
        return nil
    end

    local ok, frame = pcall(module.GenerateFrame, module, addonName .. module:GetName() .. "Preview", previewPool)
    if not ok or not frame then
        return nil
    end

    frame.isPreview = true
    module.previewFrame = frame

    return frame
end

-- True for the modules that have something worth previewing.
function XerionUIFeatures:HasPreview(module)
    return module and module.GenerateFrame and module.PreparePreview and true or false
end

-- Hangs the module's preview in `display` and draws it. Returns the frame, or nil if
-- the module has no preview to show.
--
-- `page` is optional and only means anything to a module split across tabs: it is
-- handed to PreparePreview so each tab can show the state it is configuring. It lives
-- on the display rather than in a table of its own because the display *is* the tab --
-- one per tab, and EllesmereUI hands the same one back when it restores a cached page.
function XerionUIFeatures:ShowPreview(module, display, page)
    if not self:HasPreview(module) then
        return nil
    end

    local frame = self:EnsurePreviewFrame(module)
    if not frame then
        return nil
    end

    display.previewPage = page
    self.activePreviews[module] = display
    frame:SetParent(display)
    self:RefreshPreview(module)

    return frame
end

-- Parks the preview back in the pool. `display` is optional: pass it to only release
-- a preview this host still owns, so a host tearing down a stale view cannot steal
-- one that has already moved on.
function XerionUIFeatures:HidePreview(module, display)
    if display and self.activePreviews[module] ~= display then
        return
    end

    self.activePreviews[module] = nil

    local frame = module.previewFrame
    if frame then
        frame:Hide()
        frame:ClearAllPoints()
        frame:SetParent(previewPool)
    end
end

-- Re-applies the module's settings to its preview. A no-op when no page is showing
-- one, so option setters can call it unconditionally.
function XerionUIFeatures:RefreshPreview(module)
    local display = self.activePreviews[module]
    local frame = display and module.previewFrame
    if not frame then
        return
    end

    if frame.UpdateStyles then
        pcall(frame.UpdateStyles, frame)
    end

    if module.PreparePreview then
        pcall(module.PreparePreview, module, frame, display.previewPage)
    end

    self:PinPreview(module)
end

-- Puts the preview back inside its box after the module has styled it.
--
-- UpdateStyles positions and strata the frame for its real home on UIParent, so both
-- have to be overridden: the saved point would push the preview out of the box, and a
-- BACKGROUND strata would put it behind the config window entirely.
--
-- The scale correction is EllesmereUI's own preview technique: the config window may
-- run at a different effective scale than UIParent, and without compensating, a 28px
-- font would not preview at the size it actually draws on screen.
function XerionUIFeatures:PinPreview(module)
    local display = self.activePreviews[module]
    local frame = display and module.previewFrame
    if not frame then
        return
    end

    frame:SetScale(UIParent:GetEffectiveScale() / display:GetEffectiveScale())
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", display)
    frame:SetFrameStrata(display:GetFrameStrata())
    frame:SetFrameLevel(display:GetFrameLevel() + 1)
    frame:SetAlpha(1)
    frame:Show()
end
