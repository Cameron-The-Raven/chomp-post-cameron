#define BROKEN_BONES 0x1
#define INTERNAL_BLEEDING 0x2
#define EXTERNAL_BLEEDING 0x4
#define SERIOUS_EXTERNAL_DAMAGE 0x8
#define SERIOUS_INTERNAL_DAMAGE 0x10
#define RADIATION_DAMAGE 0x20
#define TOXIN_DAMAGE 0x40
#define OXY_DAMAGE 0x80

#define HUSKED_BODY 0x100
#define WEIRD_ORGANS 0x200 //CHOMPedit malignant

// Outpost 21 addition begin
/datum/category_item/catalogue/technology/medical_kiosk
	name = "Medical Kiosk"
	desc = "A standard issue medical kiosk, also called a \"save station\". Used for scanning injuries deeper than a normal health analyzer, in addition, it scans and saves the current neural network of crew for uploading into the station's database for resleeving. Don't forget to save!"
	value = CATALOGUER_REWARD_TRIVIAL
// Outpost 21 addition end

/obj/machinery/medical_kiosk
	name = "medical kiosk"
	desc = "A helpful kiosk for finding out whatever is wrong with you."
	icon = 'icons/obj/machines/medical_kiosk.dmi'
	icon_state = "kiosk_off"
	idle_power_usage = 5
	active_power_usage = 200
	circuit = /obj/item/circuitboard/medical_kiosk
	anchored = TRUE
	density = TRUE

	var/mob/living/active_user
	var/db_key
	var/datum/transcore_db/our_db

	var/msgcooldown = 0 // Outpost 21 edit
	catalogue_data = list(/datum/category_item/catalogue/technology/medical_kiosk) // Outpost 21 edit

/obj/machinery/medical_kiosk/Initialize()
	. = ..()
	our_db = SStranscore.db_by_key(db_key)
	// Outpost 21 edit begin - Missing circuit board on deconstruct, but will eventually be removed on machine recode
	// TODO - Remove this bit once machines are converted to Initialize
	if(ispath(circuit))
		circuit = new circuit(src)
	default_apply_parts()
	// Outpost 21 edit end

/obj/machinery/medical_kiosk/update_icon()
	. = ..()
	if(panel_open)
		icon_state = "kiosk_open" // panel
	else if((stat & (NOPOWER|BROKEN)) || !active_user)
		icon_state = "kiosk_off" // asleep or no power
	else
		icon_state = "kiosk" // waiting for user or to finish processing

/obj/machinery/medical_kiosk/attack_hand(mob/living/user)
	. = ..()
	if(istype(user) && Adjacent(user))
		if(inoperable() || panel_open)
			to_chat(user, span_warning("\The [src] seems to be nonfunctional..."))
		else if(active_user && active_user != user)
			to_chat(user, span_warning("Another patient has begin using this machine. Please wait for them to finish, or their session to time out."))
		else
			start_using(user)

/obj/machinery/medical_kiosk/attackby(obj/item/O, mob/user)
	. = ..()
	if(default_unfasten_wrench(user, O, 40))
		return
	if(default_deconstruction_screwdriver(user, O))
		return
	if(default_deconstruction_crowbar(user, O))
		return
	if(default_part_replacement(user, O))
		return

/obj/machinery/medical_kiosk/proc/wake_lock(mob/living/user)
	active_user = user
	update_icon()
	update_use_power(USE_POWER_ACTIVE)

/obj/machinery/medical_kiosk/proc/suspend()
	active_user = null
	update_icon()
	update_use_power(USE_POWER_IDLE)

/obj/machinery/medical_kiosk/proc/start_using(mob/living/user)
	// Out of standby
	wake_lock(user)

	// User requests service
	user.visible_message(span_bold("[user]") + " wakes [src].", "You wake [src].")
	var/choice = tgui_alert(user, "What service would you like?", "[src]", list("Health Scan", "Backup Scan", "Cancel"), timeout = 10 SECONDS)
	if(!choice || choice == "Cancel" || !Adjacent(user) || inoperable() || panel_open)
		suspend()
		return

	// Service begins, delay
	visible_message(span_bold("\The [src]") + " scans [user] thoroughly!")
	flick("kiosk_active", src)
	if(!do_after(user, 10 SECONDS, src, exclusive = TASK_ALL_EXCLUSIVE) || inoperable())
		suspend()
		return

	// Service completes
	switch(choice)
		if("Health Scan")
			var/health_report = tell_health_info(user)
			to_chat(user, span_boldnotice("Health report results:")+health_report)
		if("Backup Scan")
			if(!our_db)
				to_chat(user, span_notice(span_bold("Backup scan results:")) + "<br>DATABASE ERROR!")
			else
				var/scan_report = do_backup_scan(user)
				to_chat(user, span_notice(span_bold("Backup scan results:"))+scan_report)

	// Standby
	suspend()

/obj/machinery/medical_kiosk/proc/tell_health_info(mob/living/user)
	if(!istype(user))
		return "<br>" + span_warning("Unable to perform diagnosis on synthetic life forms.")
	if(user.isSynthetic())
		return "<br>" + span_warning("Unable to perform diagnosis on synthetic life forms.")
	// Outpost 21 edit - Halucination replies
	if(user.hallucination > 20 && prob(30))
		return "<br>" + span_notice("[halu_text(user)]")

	var/problems = 0
	for(var/obj/item/organ/external/E in user)
		if(E.status & ORGAN_BROKEN)
			problems |= BROKEN_BONES
		if(E.status & (ORGAN_DEAD|ORGAN_DESTROYED))
			problems |= SERIOUS_EXTERNAL_DAMAGE
		if(E.status & ORGAN_BLEEDING)
			problems |= EXTERNAL_BLEEDING
		for(var/datum/wound/W in E.wounds)
			if(W.bleeding())
				if(W.internal)
					problems |= INTERNAL_BLEEDING
				else
					problems |= EXTERNAL_BLEEDING

	for(var/obj/item/organ/internal/I in user)
		if(I.status & (ORGAN_BROKEN|ORGAN_DEAD|ORGAN_DESTROYED))
			problems |= SERIOUS_INTERNAL_DAMAGE
		if(I.status & ORGAN_BLEEDING)
			problems |= INTERNAL_BLEEDING
		//CHOMPedit begin- malignants
		if(istype(I,/obj/item/organ/internal/malignant))
			problems |= WEIRD_ORGANS
		//CHOMPedit end

	if(HUSK in user.mutations)
		problems |= HUSKED_BODY
	if(user.getToxLoss() > 0)
		problems |= TOXIN_DAMAGE
	if(user.getOxyLoss() > 0)
		problems |= OXY_DAMAGE
	if(user.radiation > 0)
		problems |= RADIATION_DAMAGE
	if(user.getFireLoss() > 40 || user.getBruteLoss() > 40)
		problems |= SERIOUS_EXTERNAL_DAMAGE

	if(!problems)
		if(user.getHalLoss() > 0)
			return "<br>" + span_warning("Mild concussion detected - advising bed rest until patient feels well. No other anatomical issues detected.")
		else
			return "<br>" + span_notice("No anatomical issues detected.")

	var/problem_text = ""
	if(problems & BROKEN_BONES)
		problem_text += "<br>" + span_warning("Broken bones detected - see a medical professional and move as little as possible.")
	if(problems & INTERNAL_BLEEDING)
		problem_text += "<br>" + span_danger("Internal bleeding detected - seek medical attention, ASAP!")
	if(problems & EXTERNAL_BLEEDING)
		problem_text += "<br>" + span_warning("External bleeding detected - advising pressure with cloth and bandaging.")
	if(problems & SERIOUS_EXTERNAL_DAMAGE)
		problem_text += "<br>" + span_danger("Severe anatomical damage detected - seek medical attention.")
	if(problems & SERIOUS_INTERNAL_DAMAGE)
		problem_text += "<br>" + span_danger("Severe internal damage detected - seek medical attention.")
	if(problems & RADIATION_DAMAGE)
		problem_text += "<br>" + span_danger("Exposure to ionizing radiation detected - seek medical attention.")
	if(problems & TOXIN_DAMAGE)
		problem_text += "<br>" + span_warning("Exposure to toxic materials detected - induce vomiting if you have consumed anything recently.")
	if(problems & OXY_DAMAGE)
		problem_text += "<br>" + span_warning("Blood/air perfusion level is below acceptable norms - use concentrated oxygen if necessary.")
	//CHOMPedit begin malignants
	if(problems & WEIRD_ORGANS)
		problem_text += "<br>" + span_warning("Anatomical irregularities detected - Please see a medical professional.")
	//CHOMPedit end
	if(problems & HUSKED_BODY)
		problem_text += "<br>" + span_danger("Anatomical structure lost, resuscitation not possible!")

	return problem_text

/obj/machinery/medical_kiosk/proc/do_backup_scan(mob/living/carbon/human/user)
	if(!istype(user))
		return "<br>" + span_warning("Unable to perform full scan. Please see a medical professional.")
	if(!user.mind)
		return "<br>" + span_warning("Unable to perform full scan. Please see a medical professional.")
	// Outpost 21 edit begin - VR kiosks don't save
	if(istype(get_area(src), /area/virtual_reality))
		return "<br>" + span_warning("Backup simulation performed. Remember to backup when you leave virtual reality!")
	// Outpost 21 edit end

	/* Outpost 21 edit - Nif removal
	var/nif = user.nif
	if(nif)
		persist_nif_data(user)
	*/

	our_db.m_backup(user.mind,null /*Outpost 21 edit - Nif removal: nif */,one_time = TRUE)
	var/datum/transhuman/body_record/BR = new()
	BR.init_from_mob(user, TRUE, user.resleeve_lock, database_key = db_key) // Outpost 21 edit - Maintain resleeve_lock

	// Outpost 21 edit begin - what a mean halucination
	var/area/A = get_area(src)
	if((user.hallucination > 20 && prob(5)) || (A && A.haunted))
		return "<br>" + span_notice("Backup scan completed!") + "<br><b>Note:</b> Backup scan erased. Body scan erased. You deserve to die."

	return "<br>" + span_notice("Backup scan completed!") + "<br><b>Note:</b> Please ensure your suit's sensors are properly configured to alert medical and security personal to your current status."
	// return "<br>" + span_notice("Backup scan completed!") + "<br><b>Note:</b> A backup implant is required for automated notifications to the appropriate department in case of incident."
	// Outpost 21 edit end

// Outpost 21 edit begin - kiosk announcements
/obj/machinery/medical_kiosk/process()
	if(inoperable() || panel_open)
		return

	if(msgcooldown > 0)
		msgcooldown--
		return

	var/area/AR = get_area(src)
	if(prob(1))
		var/mob/living/carbon/halucinateTarget = null
		var/count = 0
		for(var/atom/A in view(src, 4))
			if(istype(A, /mob/living/carbon))
				count += 1
				var/mob/living/carbon/C = A
				if((C.hallucination > 20 && prob(5)) || (AR && AR.haunted))
					halucinateTarget = C

		if((count == 1 && istype(halucinateTarget,/mob/living/carbon)) || (AR && AR.haunted))
			// halucination replies
			var/text = halu_text(halucinateTarget)
			balloon_alert_visible(text)
			visible_message("\The [src] says [text]")
			msgcooldown = 60 SECONDS
		else
			// tease people to backup
			var/text = advert_text()
			balloon_alert_visible(text)
			visible_message("\The [src] says [text]")
			msgcooldown = 60 SECONDS
	return

/obj/machinery/medical_kiosk/proc/halu_text(mob/living/target)
	if(prob(15))
		return "You're not who you say you are."
	if(prob(15))
		return "I know you are lying about what you are."
	if(prob(15))
		return "Your insides are whispering."
	if(prob(15))
		return "Your flesh is whispering, it says to peel it off."
	if(prob(15) && target)
		return "Your eyes are lying to you. Wake up [target.real_name]."
	if(prob(15))
		return "Cut the bad things inside of you out."
	if(prob(15))
		return "Your not alone, it's inside you."
	if(prob(15) && target)
		return "[target.real_name]. [target.real_name]. [target.real_name]. [target.real_name]. [target.real_name]. [target.real_name]. [target.real_name]. [target.real_name]. [target.real_name]. [target.real_name]."
	if(prob(15))
		return "Stop lying to everyone, they know what is inside your body."
	if(prob(15))
		return "Everyone wants to cut you open, and take the things inside you for themselves."
	if(prob(15) && target)
		return "You are not really a [target.get_species()] are you?" // super special message
	return "Your body is wrong."

/obj/machinery/medical_kiosk/proc/advert_text()
	if(prob(15))
		return "Cherish the memories you have, save the ones you could lose"
	if(prob(15))
		return "Have you had your scan today?"
	if(prob(15))
		return "Having your backup done regularly can save you from years of legal trouble!"
	if(prob(15))
		return "Having regular backups is statistically linked to happier life outcomes!"
	if(prob(15))
		return "Going out that airlock without a backup?"
	if(prob(15))
		return "Are you sure you want to lose those memories? Backups take only a few seconds!"
	if(prob(15))
		return "A few second backup here, could save you hours in lost memories!"
	if(prob(15))
		return "You almost dropped those life long memories! Back them up while you can!"
	return "Are you in compliance? Get backed up today!"
// Outpost 21 edit end

#undef BROKEN_BONES
#undef INTERNAL_BLEEDING
#undef EXTERNAL_BLEEDING
#undef SERIOUS_EXTERNAL_DAMAGE
#undef SERIOUS_INTERNAL_DAMAGE
#undef RADIATION_DAMAGE
#undef TOXIN_DAMAGE
#undef OXY_DAMAGE

#undef HUSKED_BODY
#undef WEIRD_ORGANS // CHOMPedit - malignants
