local info = debug.getinfo(1, "S")
local script_path = info.source:match("@(.+)[/\\]")

package.path = script_path ..
    "/reaper_objects_wrappers/?.lua;"  ..
    "/reaper_objects_wrappers/track_utils/?.lua;" ..
    "/reaper_objects_wrappers/env_utils/?.lua;" ..
    package.path

local Track = require("track")
local FX = require("fx")
local RenderingUtil = require("rendering_utils")


local TRACK_NAME = "TrackPrint"
local TARGET_LUFS = -23
local MAX_DELTA = 16
local TOLERANCE = 0.5


local function begin_edit()
  reaper.Undo_BeginBlock()
  reaper.PreventUIRefresh(1)
end

local function end_edit(desc)
  reaper.PreventUIRefresh(-1)
  reaper.Undo_EndBlock(desc, -1)
end

local function volume_normalizer()


    local track = Track.new(0, TRACK_NAME)
    if track == nil then return false, "Track not found" end

    reaper.Main_OnCommand(40297, 0) -- unselect all tracks
    reaper.SetOnlyTrackSelected(track.track)

    local function get_cur_track_stats()
        local cur_stats = RenderingUtil.parse_render_stats(RenderingUtil.measure_and_read_render_stats(0, 0))
        if cur_stats == nil or #cur_stats == 0 then return nil, "error reading stats" end
        local cur_track_stats = RenderingUtil.get_record_by_filename(track, cur_stats, TRACK_NAME)

        if not cur_track_stats then return nil, "stats record for track not found" end
        if cur_track_stats.lufsi == nil then return nil, "lufsi missing" end

        return cur_track_stats, "success"
    end


    local volume_adjuster_fx = FX.new(track.track, 0)
    local param_index = FX.get_paramidx_by_name(volume_adjuster_fx, "Adjustment (dB)")
    local param_value_status, string_value = reaper.TrackFX_GetFormattedParamValue(track.track, volume_adjuster_fx.addrs, param_index)

    if not param_value_status then return false, "Couldn't read volume value" end

    local volume_adjuster_current_value = tonumber(string_value)
    if volume_adjuster_current_value == nil then return false, "Couldn't read volume value" end

    local stats, stats_status = get_cur_track_stats()
    if stats == nil then return false, stats_status end

    local delta_db = TARGET_LUFS - stats.lufsi
    if math.abs(delta_db) > MAX_DELTA then return false, "too big delta. Adjust overall mix" end

    local db_to_set = volume_adjuster_current_value + delta_db
    local set_value_status = reaper.TrackFX_SetParam(track.track, volume_adjuster_fx.addrs, param_index, db_to_set)

    if not set_value_status then return false, "Error setting value" end

    local after_stats, after_stats_status = get_cur_track_stats()
    if after_stats == nil then
        local set_old_value_status = reaper.TrackFX_SetParam(track.track, volume_adjuster_fx.addrs, param_index, volume_adjuster_current_value)
        if not set_old_value_status then 
            after_stats_status = after_stats_status.. "\nReverting to old value have failed"
        else
            after_stats_status = after_stats_status .. "\nReverted to the old value"
        end
        return false, after_stats_status
    end

    if math.abs(after_stats.lufsi - TARGET_LUFS) < TOLERANCE then
        local set_old_value_status = reaper.TrackFX_SetParam(track.track, volume_adjuster_fx.addrs, param_index, volume_adjuster_current_value)
        local msg = "Adjustment failed"
        if not set_old_value_status then 
            msg = msg.. "\nReverting to old value have failed"
        else
            msg = msg .. "\nReverted to the old value"
        end

        return false, msg
    end

    return true, "Success"




end



reaper.ClearConsole()
begin_edit()

local ok, msg = volume_normalizer()
if not ok then reaper.ShowMessageBox(msg, "Error", 0) end

end_edit("Normalize Track Print in Time selection")
