local krpc = require 'krpc'

local turn_start_altitude = 250
local turn_end_altitude = 45000
local target_altitude = 150000

local conn = krpc:connect('Launch into orbit')
local vessel = conn.space_center.active_vessel

-- Set up streams for telemetry
--ut = conn.add_stream(getattr, conn.space_center, 'ut')
--altitude = conn.add_stream(getattr, vessel.flight(), 'mean_altitude')
--apoapsis = conn.add_stream(getattr, vessel.orbit, 'apoapsis_altitude')
--stage_3_resources = vessel.resources_in_decouple_stage(stage=3, cumulative=False)
--srb_fuel = conn.add_stream(stage_3_resources.amount, 'SolidFuel')

-- Pre-launch setup
vessel.control.sas = False
vessel.control.rcs = False
vessel.control.throttle = 1

-- Countdown...
print('3...')
time.sleep(1)
print('2...')
time.sleep(1)
print('1...')
time.sleep(1)
print('Launch!')

-- Activate the first stage
vessel.control:activate_next_stage()
vessel.auto_pilot:engage()
vessel.auto_pilot:target_pitch_and_heading(90, 90)

-- Main ascent loop
local srbs_separated = False
local turn_angle = 0
while True do

    -- Gravity turn
    if altitude() > turn_start_altitude and altitude() < turn_end_altitude then
        frac = (altitude() - turn_start_altitude) / (turn_end_altitude - turn_start_altitude)
        new_turn_angle = frac * 90
        if abs(new_turn_angle - turn_angle) > 0.5 then
            turn_angle = new_turn_angle
            vessel.auto_pilot:target_pitch_and_heading(90-turn_angle, 90)
        end
    end

    -- Separate SRBs when finished
    if not srbs_separated then
        if srb_fuel() < 0.1 then
            vessel.control:activate_next_stage()
            srbs_separated = True
            print('SRBs separated')
        end
    end

    -- Decrease throttle when approaching target apoapsis
    if apoapsis() > target_altitude*0.9 then
        print('Approaching target apoapsis')
        break
    end
end

-- Disable engines when target apoapsis is reached
vessel.control.throttle = 0.25
while apoapsis() < target_altitude do
end
print('Target apoapsis reached')
vessel.control.throttle = 0

-- Wait until out of atmosphere
print('Coasting out of atmosphere')
while altitude() < 70500 do
end

-- Plan circularization burn (using vis-viva equation)
print('Planning circularization burn')
local mu = vessel.orbit.body.gravitational_parameter
local r = vessel.orbit.apoapsis
local a1 = vessel.orbit.semi_major_axis
local a2 = r
local v1 = math.sqrt(mu*((2./r)-(1./a1)))
local v2 = math.sqrt(mu*((2./r)-(1./a2)))
local delta_v = v2 - v1
local node = vessel.control:add_node(ut() + vessel.orbit.time_to_apoapsis, delta_v, 0, 0)

-- Calculate burn time (using rocket equation)
local F = vessel.available_thrust
local Isp = vessel.specific_impulse * 9.82
local m0 = vessel.mass
local m1 = m0 / math.exp(delta_v/Isp)
local flow_rate = F / Isp
local burn_time = (m0 - m1) / flow_rate

-- Orientate ship
print('Orientating ship for circularization burn')
vessel.auto_pilot.reference_frame = node.reference_frame
vessel.auto_pilot.target_direction = {0, 1, 0}
vessel.auto_pilot:wait()

-- Wait until burn
print('Waiting until circularization burn')
local burn_ut = ut() + vessel.orbit.time_to_apoapsis - (burn_time/2.)
local lead_time = 5
conn.space_center:warp_to(burn_ut - lead_time)

-- Execute burn
print('Ready to execute burn')
time_to_apoapsis = conn.add_stream(getattr, vessel.orbit, 'time_to_apoapsis')
while time_to_apoapsis() - (burn_time/2.) > 0 do
end
print('Executing burn')
vessel.control.throttle = 1
time.sleep(burn_time - 0.1)
print('Fine tuning')
vessel.control.throttle = 0.05
remaining_burn = conn.add_stream(node.remaining_burn_vector, node.reference_frame)
while remaining_burn()[2] > 0 do
end
vessel.control.throttle = 0
node:remove()

print('Launch complete')
