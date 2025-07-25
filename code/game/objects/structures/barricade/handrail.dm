/obj/structure/barricade/handrail
	name = "handrail"
	desc = "A railing, for your hands. Woooow."
	icon = 'icons/obj/structures/handrail.dmi'
	icon_state = "handrail_a_0"
	barricade_type = "handrail"
	health = 30
	maxhealth = 30
	climb_delay = CLIMB_DELAY_SHORT
	stack_type = /obj/item/stack/sheet/metal
	debris = list(/obj/item/stack/sheet/metal)
	stack_amount = 2
	destroyed_stack_amount = 1
	crusher_resistant = FALSE
	can_wire = FALSE
	barricade_hitsound = 'sound/effects/metalhit.ogg'
	projectile_coverage = PROJECTILE_COVERAGE_MINIMAL
	var/build_state = BARRICADE_BSTATE_SECURED
	var/reinforced = FALSE //Reinforced to be a cade or not
	var/can_be_reinforced = TRUE //can we even reinforce this handrail or not?
	///Whether a ground z-level handrail allows auto-climbing on harm intent
	var/autoclimb = TRUE

/obj/structure/barricade/handrail/Initialize(mapload, ...)
	. = ..()
	if(!is_ground_level(z))
		if(autoclimb && is_mainship_level(z))
			RegisterSignal(SSdcs, COMSIG_GLOB_HIJACK_LANDED, PROC_REF(reset_autoclimb))
		autoclimb = FALSE

/obj/structure/barricade/handrail/proc/reset_autoclimb()
	autoclimb = initial(autoclimb)

/obj/structure/barricade/handrail/update_icon()
	overlays.Cut()
	switch(dir)
		if(SOUTH)
			layer = ABOVE_MOB_LAYER
		if(NORTH)
			layer = initial(layer) - 0.01
		else
			layer = initial(layer)
	pixel_y = initial(pixel_y)
	if(!anchored)
		pixel_y += 2
	if(build_state == BARRICADE_BSTATE_FORTIFIED)
		if(reinforced)
			overlays += image('icons/obj/structures/handrail.dmi', icon_state = "[barricade_type]_reinforced_[damage_state]")
		else
			overlays += image('icons/obj/structures/handrail.dmi', icon_state = "[barricade_type]_welder_step")

	for(var/datum/effects/E in effects_list)
		if(E.icon_path && E.obj_icon_state_path)
			overlays += image(E.icon_path, icon_state = E.obj_icon_state_path)

/obj/structure/barricade/handrail/Collided(atom/movable/movable)
	if(!ismob(movable))
		return ..()

	if(istype(movable, /mob/living/carbon/xenomorph/ravager) || istype(movable, /mob/living/carbon/xenomorph/crusher))
		var/mob/living/carbon/xenomorph/xenomorph = movable
		if(!xenomorph.stat)
			visible_message(SPAN_DANGER("[xenomorph] plows straight through [src]!"))
			deconstruct(FALSE)
			return
	else
		if(!autoclimb)
			return ..()

		if(movable.last_bumped == world.time)
			return ..()

		var/mob/living/climber = movable
		if(climber.a_intent != INTENT_HARM)
			return ..()

		climber.client?.move_delay += 3 DECISECONDS
		if(do_climb(climber))
			if(prob(25))
				if(ishuman(climber))
					var/mob/living/carbon/human/human = climber
					human.apply_damage(5, BRUTE, no_limb_loss = TRUE)
				else
					climber.apply_damage(5, BRUTE)
				climber.visible_message(SPAN_WARNING("[climber] injures themselves vaulting over [src]."), SPAN_WARNING("You hit yourself as you vault over [src]."))
	..()

/obj/structure/barricade/handrail/get_examine_text(mob/user)
	. = ..()
	switch(build_state)
		if(BARRICADE_BSTATE_SECURED)
			. += SPAN_INFO("The [barricade_type] is safely secured to the ground.")
		if(BARRICADE_BSTATE_UNSECURED)
			. += SPAN_INFO("The bolts nailing it to the ground has been unsecured.")
		if(BARRICADE_BSTATE_FORTIFIED)
			if(reinforced)
				. += SPAN_INFO("The [barricade_type] has been reinforced with metal.")
			else
				. += SPAN_INFO("Metal has been laid across the [barricade_type]. Weld it to secure it.")

/obj/structure/barricade/handrail/proc/reinforce()
	if(reinforced)
		if(health == maxhealth) // Drop metal if full hp when unreinforcing
			new /obj/item/stack/sheet/metal(loc)
		health = initial(health)
		maxhealth = initial(maxhealth)
		projectile_coverage = initial(projectile_coverage)
	else
		health = 350
		maxhealth = 350
		projectile_coverage = PROJECTILE_COVERAGE_HIGH
	reinforced = !reinforced
	update_icon()

/obj/structure/barricade/handrail/attackby(obj/item/item, mob/user)
	for(var/obj/effect/xenomorph/acid/A in src.loc)
		if(A.acid_t == src)
			to_chat(user, "You can't get near that, it's melting!")
			return

	switch(build_state)
		if(BARRICADE_BSTATE_SECURED) //Non-reinforced. Wrench to unsecure. Screwdriver to disassemble into metal. 1 metal to reinforce.
			if(HAS_TRAIT(item, TRAIT_TOOL_WRENCH)) // Make unsecure
				if(user.action_busy)
					return
				if(!skillcheck(user, SKILL_CONSTRUCTION, SKILL_CONSTRUCTION_TRAINED))
					to_chat(user, SPAN_WARNING("You are not trained to unsecure [src]..."))
					return
				playsound(src.loc, 'sound/items/Ratchet.ogg', 25, 1)
				if(!do_after(user, 10, INTERRUPT_ALL|BEHAVIOR_IMMOBILE, BUSY_ICON_BUILD, src))
					return
				user.visible_message(SPAN_NOTICE("[user] loosens [src]'s anchor bolts."),
				SPAN_NOTICE("You loosen [src]'s anchor bolts."))
				anchored = FALSE
				build_state = BARRICADE_BSTATE_UNSECURED
				update_icon()
				return
			if(istype(item, /obj/item/stack/sheet/metal)) // Start reinforcing
				if(!can_be_reinforced)
					return
				if(user.action_busy)
					return
				if(!skillcheck(user, SKILL_CONSTRUCTION, SKILL_CONSTRUCTION_TRAINED))
					to_chat(user, SPAN_WARNING("You are not trained to reinforce [src]..."))
					return
				var/obj/item/stack/sheet/metal/M = item
				playsound(src.loc, 'sound/items/Screwdriver2.ogg', 25, 1)
				if(M.amount >= 1 && do_after(user, 30, INTERRUPT_ALL|BEHAVIOR_IMMOBILE, BUSY_ICON_BUILD)) //Shouldnt be possible, but doesnt hurt to check
					if(!M.use(1))
						return
					build_state = BARRICADE_BSTATE_FORTIFIED
					update_icon()
				else
					to_chat(user, SPAN_WARNING("You need at least one metal sheet to do this."))
				return

		if(BARRICADE_BSTATE_UNSECURED)
			if(HAS_TRAIT(item, TRAIT_TOOL_WRENCH)) // Secure again
				if(user.action_busy)
					return
				if(!skillcheck(user, SKILL_CONSTRUCTION, SKILL_CONSTRUCTION_TRAINED))
					to_chat(user, SPAN_WARNING("You are not trained to secure [src]..."))
					return
				playsound(src.loc, 'sound/items/Ratchet.ogg', 25, 1)
				if(!do_after(user, 10, INTERRUPT_ALL|BEHAVIOR_IMMOBILE, BUSY_ICON_BUILD, src))
					return
				user.visible_message(SPAN_NOTICE("[user] tightens [src]'s anchor bolts."),
				SPAN_NOTICE("You tighten [src]'s anchor bolts."))
				anchored = TRUE
				build_state = BARRICADE_BSTATE_SECURED
				update_icon()
				return
			if(HAS_TRAIT(item, TRAIT_TOOL_SCREWDRIVER)) // Disassemble into metal
				if(user.action_busy)
					return
				if(!skillcheck(user, SKILL_CONSTRUCTION, SKILL_CONSTRUCTION_TRAINED))
					to_chat(user, SPAN_WARNING("You are not trained to disassemble [src]..."))
					return
				user.visible_message(SPAN_NOTICE("[user] starts unscrewing [src]'s panels."),
				SPAN_NOTICE("You remove [src]'s panels and start taking it apart."))
				playsound(src.loc, 'sound/items/Screwdriver.ogg', 25, 1)
				if(!do_after(user, 10, INTERRUPT_ALL|BEHAVIOR_IMMOBILE, BUSY_ICON_BUILD, src))
					return
				user.visible_message(SPAN_NOTICE("[user] takes apart [src]."),
				SPAN_NOTICE("You take apart [src]."))
				playsound(loc, 'sound/items/Deconstruct.ogg', 25, 1)
				deconstruct(TRUE)
				return

		if(BARRICADE_BSTATE_FORTIFIED)
			if(reinforced)
				if(HAS_TRAIT(item, TRAIT_TOOL_CROWBAR)) // Un-reinforce
					if(user.action_busy)
						return
					if(!skillcheck(user, SKILL_CONSTRUCTION, SKILL_CONSTRUCTION_TRAINED))
						to_chat(user, SPAN_WARNING("You are not trained to unreinforce [src]..."))
						return
					playsound(src.loc, 'sound/items/Crowbar.ogg', 25, 1)
					if(!do_after(user, 10, INTERRUPT_ALL|BEHAVIOR_IMMOBILE, BUSY_ICON_BUILD, src))
						return
					user.visible_message(SPAN_NOTICE("[user] pries off [src]'s extra metal panel."),
					SPAN_NOTICE("You pry off [src]'s extra metal panel."))
					build_state = BARRICADE_BSTATE_SECURED
					reinforce()
					return
			else
				if(iswelder(item)) // Finish reinforcing
					if(!HAS_TRAIT(item, TRAIT_TOOL_BLOWTORCH))
						to_chat(user, SPAN_WARNING("You need a stronger blowtorch!"))
						return
					if(user.action_busy)
						return
					if(!skillcheck(user, SKILL_CONSTRUCTION, SKILL_CONSTRUCTION_TRAINED))
						to_chat(user, SPAN_WARNING("You are not trained to reinforce [src]..."))
						return
					playsound(src.loc, 'sound/items/Welder.ogg', 25, 1)
					if(!do_after(user, 10, INTERRUPT_ALL|BEHAVIOR_IMMOBILE, BUSY_ICON_BUILD, src))
						return
					user.visible_message(SPAN_NOTICE("[user] secures [src]'s metal panel."),
					SPAN_NOTICE("You secure [src]'s metal panel."))
					reinforce()
					return
	. = ..()

/obj/structure/barricade/handrail/no_vault
	autoclimb = FALSE

/obj/structure/barricade/handrail/type_b
	icon_state = "handrail_b_0"

/obj/structure/barricade/handrail/strata
	icon_state = "handrail_strata"

/obj/structure/barricade/handrail/medical
	icon_state = "handrail_med"

/obj/structure/barricade/handrail/kutjevo
	icon_state = "hr_kutjevo"

/obj/structure/barricade/handrail/wire
	icon_state = "wire_rail"
	climb_delay = CLIMB_DELAY_SHORT

/obj/structure/barricade/handrail/sandstone
	name = "sandstone handrail"
	icon_state = "hr_sandstone"
	can_be_reinforced = FALSE
	projectile_coverage = PROJECTILE_COVERAGE_LOW
	stack_type = /obj/item/stack/sheet/mineral/sandstone
	debris = list(/obj/item/stack/sheet/mineral/sandstone)

/obj/structure/barricade/handrail/sandstone/b
	icon_state = "hr_sandstone_b"

/obj/structure/barricade/handrail/sandstone/dark
	color = "#2E1E21"

/obj/structure/barricade/handrail/sandstone/b/dark
	color = "#2E1E21"

/obj/structure/barricade/handrail/pizza
	name = "\improper diner half-wall"
	icon_state = "hr_sandstone" //temp, getting sprites soontm
	color = "#b51c0b"
	can_be_reinforced = FALSE
	projectile_coverage = PROJECTILE_COVERAGE_LOW
	layer = MOB_LAYER + 0.01

/obj/structure/barricade/handrail/pizza
	name = "\improper diner half-wall"
	icon_state = "hr_sandstone" //temp, getting sprites soontm
	color = "#b51c0b"
	can_be_reinforced = FALSE
	projectile_coverage = PROJECTILE_COVERAGE_LOW
	layer = MOB_LAYER + 0.01

// Hybrisa Barricades

/obj/structure/barricade/handrail/hybrisa
	icon_state = "plasticroadbarrierred"
	stack_amount = 0 //we do not want it to drop any stuff when destroyed
	destroyed_stack_amount = 0

// Plastic
/obj/structure/barricade/handrail/hybrisa/road/plastic
	name = "plastic road barrier"
	icon_state = "plasticroadbarrierred"
	barricade_hitsound = 'sound/effects/thud.ogg'

/obj/structure/barricade/handrail/hybrisa/road/plastic/red
	name = "plastic road barrier"
	icon_state = "plasticroadbarrierred"

/obj/structure/barricade/handrail/hybrisa/road/plastic/blue
	name = "plastic road barrier"
	icon_state = "plasticroadbarrierblue"

/obj/structure/barricade/handrail/hybrisa/road/plastic/black
	name = "plastic road barrier"
	icon_state = "plasticroadbarrierblack"

//Wood

/obj/structure/barricade/handrail/hybrisa/road/wood
	name = "wood road barrier"
	icon_state = "roadbarrierwood"
	barricade_hitsound = 'sound/effects/woodhit.ogg'

/obj/structure/barricade/handrail/hybrisa/road/wood/orange
	name = "wood road barrier"
	icon_state = "roadbarrierwood"

/obj/structure/barricade/handrail/hybrisa/road/wood/blue
	name = "wood road barrier"
	icon_state = "roadbarrierpolice"

// Metal Road Barrier

/obj/structure/barricade/handrail/hybrisa/road/metal
	name = "metal road barrier"
	icon_state = "centerroadbarrier"

/obj/structure/barricade/handrail/hybrisa/road/metal/metaltan
	name = "metal road barrier"
	icon_state = "centerroadbarrier"

/obj/structure/barricade/handrail/hybrisa/road/metal/metaltan/middle
	name = "metal road barrier"
	icon_state = "centerroadbarrier_middle"

/obj/structure/barricade/handrail/hybrisa/road/metal/metaldark
	name = "metal road barrier"
	icon_state = "centerroadbarrier2"

/obj/structure/barricade/handrail/hybrisa/road/metal/metaldark/middle
	name = "metal road barrier"
	icon_state = "centerroadbarrier2_middle"

/obj/structure/barricade/handrail/hybrisa/road/metal/metaldark2
	name = "metal road barrier"
	icon_state = "centerroadbarrier3"

/obj/structure/barricade/handrail/hybrisa/road/metal/metaldark2/middle
	name = "metal road barrier"
	icon_state = "centerroadbarrier3_middle"

/obj/structure/barricade/handrail/hybrisa/road/metal/double
	name = "metal road barrier"
	icon_state = "centerroadbarrierdouble"

/obj/structure/barricade/handrail/hybrisa/handrail
	name = "handrail"
	icon_state = "handrail_hybrisa"
