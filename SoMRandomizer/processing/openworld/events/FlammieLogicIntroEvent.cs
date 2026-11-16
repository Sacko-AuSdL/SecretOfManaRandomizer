using SoMRandomizer.config.settings;
using SoMRandomizer.processing.common;
using SoMRandomizer.processing.common.structure;

namespace SoMRandomizer.processing.openworld.events
{
    /// <summary>
    /// Open world intro event for flammie drum in logic.
    /// </summary>
    /// 
    /// <remarks>Author: Moppleton</remarks>
    class FlammieLogicIntroEvent : RandoProcessor
    {
        protected override string getName()
        {
            return "Event 0x106 - intro (flammie drum in logic)";
        }

        protected override bool process(byte[] origRom, byte[] outRom, string seed, RandoSettings settings, RandoContext context)
        {
            if(!settings.getBool(OpenWorldSettings.PROPERTYNAME_FLAMMIE_DRUM_IN_LOGIC))
            {
                return false;
            }
            if (context.workingData.get(OpenWorldGoalProcessor.GOAL_SHORT_NAME) == OpenWorldGoalProcessor.GOAL_GIFTMODE ||
                context.workingData.get(OpenWorldGoalProcessor.GOAL_SHORT_NAME) == OpenWorldGoalProcessor.GOAL_REINDEER)
            {
                // keep the christmas start text
                return false;
            }

            EventScript eventData = (EventScript)context.replacementEvents[0x106];
            if(OpenWorldStartingLocation.useKakkara(settings, context))
            {
                // Use Kakkara's existing town-theme event after the startup door transition.
                eventData.Jsr(OpenWorldStartingLocation.KAKKARA_MUSIC_EVENT);
            }
            else if(OpenWorldStartingLocation.useAlternateStart(settings, context))
            {
                var town = OpenWorldStartingLocation.getTown(settings, context);
                // Native town music events END rather than RETURN: copy only their
                // sound command so initialization and Sword acquisition continue.
                var music = VanillaEventUtil.getVanillaEvent(origRom, town.MusicEvent);
                if (music.Count < 5 || music[0] != EventCommandEnum.PLAY_SOUND.Value)
                    throw new System.InvalidOperationException("Native starting-town music contract changed.");
                eventData.SetFlag(0xFD, (byte)(town.Map == OpenWorldStartingLocation.ICE_COUNTRY_MAP ? 0 : 1));
                eventData.SetFlag(0xFE, (byte)(town.Map == OpenWorldStartingLocation.ICE_COUNTRY_MAP ? 13 : 0));
                eventData.AddRange(music.GetRange(0, 5));
            }
            else
            {
                eventData.Add(EventCommandEnum.PLAY_SOUND.Value);
                eventData.Add(0x01);
                eventData.Add(0x11);
                eventData.Add(0x12);
                eventData.Add(0x8f);
            }

            eventData.AddAutoTextDialogueBox(VanillaEventUtil.wordWrapText("Starting here because flammie drum is in logic! Give it a second here it's got a lot to set up"), 0x0A);

            // event 0x107 - initialize event flags
            eventData.Jsr(0x107);

            // -> event x103, the sword grab event
            eventData.Jump(0x103);
            eventData.End();
            return true;
        }
    }
}
