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


local function volume_normalizer()

    local ts_start, ts_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if ts_start >= ts_end then
        return false, "No time selection. Create a time selection first"
    end



    local track = Track.new(0, TRACK_NAME)
    if track == nil then return false, "Track not found" end

    reaper.Main_OnCommand(40297, 0) -- unselect all tracks
    reaper.SetOnlyTrackSelected(track.track)

    local function get_cur_track_stats()
        local cur_stats = RenderingUtil.parse_render_stats(RenderingUtil.measure_and_read_render_stats(0, 1))
        if cur_stats == nil or #cur_stats == 0 then return nil, "error reading stats" end
        local cur_track_stats = RenderingUtil.get_record_by_filename(track, cur_stats, TRACK_NAME)

        if not cur_track_stats then return nil, "stats record for track not found" end
        if cur_track_stats.lufsi == nil then return nil, "lufsi missing" end

        return cur_track_stats, "success"
    end


    local volume_adjuster_fx = FX.new(track.track, 0)
    local param_index = FX.get_paramidx_by_name(volume_adjuster_fx, "Adjustment (dB)")
    local volume_adjuster_current_value, min, max = reaper.TrackFX_GetParam(track.track, volume_adjuster_fx.addrs, param_index)


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

    if math.abs(after_stats.lufsi - TARGET_LUFS) > TOLERANCE then
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


local function run_with_undo(desc, func)
    reaper.ClearConsole()
    local began = false
    local ok, err

    ok, err = xpcall(function ()
        reaper.Undo_BeginBlock()
        reaper.PreventUIRefresh(1)
        began = true
        func()
    end, debug.traceback)

    if began then
        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock(desc, -1)
    end

    if not ok and err ~= nil then
        reaper.ShowMessageBox(err, "Script error", 0)
    end

    return ok, err
end


run_with_undo("Normalize Track Print to -23 LUFS", function ()
    local ok, msg = volume_normalizer()
    if not ok then
        error(msg)
    end
end)
