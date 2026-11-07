# frozen_string_literal: true

require "episode_description_parser"

# Covers the 13 upstream test cases in
# podcasts-gtk/src/episode_description_parser.rs's `#[cfg(test)] mod tests`,
# one `it` per upstream `#[test] fn`, named after the upstream fn and in the
# same order. Each case's `description` and `expected` are the upstream
# fixture strings, copied verbatim.
#
# This file exists because .reports/component-inventory.md claimed these 13
# cases were ported "byte for byte" with no spec file anywhere backing that
# claim (see .reports/accountability-ensurance.md). Running this file is how
# that claim gets to be true or gets corrected.
RSpec.describe EpisodeDescriptionParser do
  def markup_for(description)
    described_class.html_to_pango_markup(description)
  end

  # fn test_html_based
  it "test_html_based" do
    description = "<p>Here is an unlocked Britainology to hopefully brighten your weekend. Yes, it was a little bit late when it came out. It was late because Nate and Milo got exposed to covid right before Christmas and couldn't record while waiting on test results. But we have in fact discussed Jim Davidson's terrible bawdy Cinderella pantomime from 1995, entitled 'Sinderella', and discussed the concept of pantos in general. Hope you enjoy!</p>\n\n<p>We've also unlocked the Dogging episode of Britainology to the $5 tier--get it here: <a href=\"https://www.patreon.com/posts/51682396\">https://www.patreon.com/posts/51682396</a></p>\n\n<p>And if you want two (2) Britainologies a month, sign up on the $10 tier on Patreon! This month's second episode features us discussing the British Army with friend of the show, veteran, leftist, and author Joe Glenton: <a href=\"https://www.patreon.com/posts/56590770\">https://www.patreon.com/posts/56590770</a></p>\n\n<p>*MILO ALERT* Smoke returns for another night of new material from pro-comics featuring Edinburgh Comedy Award winner Jordan Brookes. See it all, for the low price of £5, on September 28 at 8 pm at The Sekforde Arms (34 Sekforde Street London EC1R 0HA): <a href=\"https://www.eventbrite.co.uk/e/smoke-comedy-featuring-jordan-brookes-tickets-171869475227\">https://www.eventbrite.co.uk/e/smoke-comedy-featuring-jordan-brookes-tickets-171869475227</a></p>\n\n<p>Trashfuture are: Riley (<a href=\"https://twitter.com/raaleh\">@raaleh</a>), Milo (<a href=\"https://twitter.com/Milo_Edwards\">@Milo_Edwards</a>), Hussein (<a href=\"https://twitter.com/HKesvani\">@HKesvani</a>), Nate (<a href=\"https://twitter.com/inthesedeserts\">@inthesedeserts</a>), and Alice (<a href=\"https://twitter.com/AliceAvizandum\">@AliceAvizandum</a>)</p>"
    expected = "Here is an unlocked Britainology to hopefully brighten your weekend. Yes, it was a little bit late when it came out. It was late because Nate and Milo got exposed to covid right before Christmas and couldn't record while waiting on test results. But we have in fact discussed Jim Davidson's terrible bawdy Cinderella pantomime from 1995, entitled 'Sinderella', and discussed the concept of pantos in general. Hope you enjoy!\n\nWe've also unlocked the Dogging episode of Britainology to the $5 tier--get it here: <a href=\"https://www.patreon.com/posts/51682396\">https://www.patreon.com/posts/51682396</a>\n\nAnd if you want two (2) Britainologies a month, sign up on the $10 tier on Patreon! This month's second episode features us discussing the British Army with friend of the show, veteran, leftist, and author Joe Glenton: <a href=\"https://www.patreon.com/posts/56590770\">https://www.patreon.com/posts/56590770</a>\n\n*MILO ALERT* Smoke returns for another night of new material from pro-comics featuring Edinburgh Comedy Award winner Jordan Brookes. See it all, for the low price of £5, on September 28 at 8 pm at The Sekforde Arms (34 Sekforde Street London EC1R 0HA): <a href=\"https://www.eventbrite.co.uk/e/smoke-comedy-featuring-jordan-brookes-tickets-171869475227\">https://www.eventbrite.co.uk/e/smoke-comedy-featuring-jordan-brookes-tickets-171869475227</a>\n\nTrashfuture are: Riley (<a href=\"https://twitter.com/raaleh\">@raaleh</a>), Milo (<a href=\"https://twitter.com/Milo_Edwards\">@Milo_Edwards</a>), Hussein (<a href=\"https://twitter.com/HKesvani\">@HKesvani</a>), Nate (<a href=\"https://twitter.com/inthesedeserts\">@inthesedeserts</a>), and Alice (<a href=\"https://twitter.com/AliceAvizandum\">@AliceAvizandum</a>)\n\n"

    expect(markup_for(description)).to eq(expected)
  end

  # fn test_html_based2
  it "test_html_based2" do
    description = "<p>So, in rank defiance of our recent promise to 'get back to the nazis' instead we continue our James Lindsay coverage.&nbsp; (What... me? Irony? How dare you?)&nbsp; This time, Daniel patiently walks a distracted, slightly hyperactive, and increasingly incredulous Jack through the infamous 'Grievance Studies Hoax' (AKA 'Sokal Squared') in which Lindsay and colleagues Helen Pluckrose and Peter Boghossian tried (and then claimed) to prove something or other about modern Humanities academia by submitting a load of stupid fake papers to various feminist and fat studies journals.&nbsp; As Daniel reveals, the episode was an orgy of dishonesty and tactical point-missing that actually proved the opposite of what the team of snickering tricksters thought they were proving.&nbsp; Sadly, however, because we live in Hell, the trio have only raised their profiles as a result.&nbsp; A particular highlight of the episode is Lindsay revealing his staggering ignorance when 'responding' to criticism.</p> <p>Content warnings, as ever.</p> <p><span>Podcast Notes:</span></p> <p>Please consider donating to help us make the show and stay independent.&nbsp; Patrons get exclusive access to one full extra episode a month.</p> <p>Daniel's Patreon: <a href=\"https://www.patreon.com/danielharper\">https://www.patreon.com/danielharper</a></p> <p>Jack's Patreon: <a href=\"https://www.patreon.com/user?u=4196618&amp;fan_landing=true\">https://www.patreon.com/user?u=4196618</a></p> <p>IDSG Twitter: <a href=\"https://twitter.com/idsgpod\">https://twitter.com/idsgpod</a></p> <p>Daniel's Twitter: <a href=\"https://twitter.com/danieleharper\">@danieleharper</a></p> <p>Jack's Twitter: <a href=\"https://twitter.com/_Jack_Graham_\">@_Jack_Graham_</a></p> <p>IDSG on Apple Podcasts: <a href=\"https://podcasts.apple.com/us/podcast/i-dont-speak-german/id1449848509?ls=1\"> https://podcasts.apple.com/us/podcast/i-dont-speak-german/id1449848509?ls=1</a></p> <p>&nbsp;</p> <p><span>Show Notes:</span></p> <p>James Lindsay, New Discourses, \"Why You Can Be Transgender But Not Transracial.\"\" <a href=\"https://newdiscourses.com/2021/06/why-you-can-be-transgender-but-not-transracial/\"> https://newdiscourses.com/2021/06/why-you-can-be-transgender-but-not-transracial/</a></p> <p>James Lindsay has a day job, apparently. \"Maryville man walks path of healing and combat.\" <a href=\"https://www.thedailytimes.com/news/maryville-man-walks-path-of-healing-and-combat/article_5ea3c0ca-2e98-5283-9e59-06861b8588cb.html\"> https://www.thedailytimes.com/news/maryville-man-walks-path-of-healing-and-combat/article_5ea3c0ca-2e98-5283-9e59-06861b8588cb.html</a></p> <p>Areo Magazine, Academic Grievance Studies and the Corruption of Scholarship. <a href=\"https://areomagazine.com/2018/10/02/academic-grievance-studies-and-the-corruption-of-scholarship/\"> https://areomagazine.com/2018/10/02/academic-grievance-studies-and-the-corruption-of-scholarship/</a></p> <p>Full listing of Grievance Studies Papers and Reviews. <a href=\"https://drive.google.com/drive/folders/19tBy_fVlYIHTxxjuVMFxh4pqLHM_en18\"> https://drive.google.com/drive/folders/19tBy_fVlYIHTxxjuVMFxh4pqLHM_en18</a></p> <p>'Mein Kampf' and the 'Feminazis': What Three Academics' Hitler Hoax Really Reveals About 'Wokeness'. <a href=\"https://web.archive.org/web/20210328112901/https://www.haaretz.com/us-news/.premium-hitler-hoax-academic-wokeness-culture-war-1.9629759\"> https://web.archive.org/web/20210328112901/https://www.haaretz.com/us-news/.premium-hitler-hoax-academic-wokeness-culture-war-1.9629759</a></p> <p>\"First and foremost, the source material. The chapter the hoaxers chose, not by coincidence, one of the least ideological and racist parts of Hitler's book. Chapter 12, probably written in April/May 1925, deals with how the newly refounded NSDAP should rebuild as a party and amplify its program.</p> <p>\"According to their own account, the writers took parts of the chapter and inserted feminist \"buzzwords\"; they \"significantly changed\" the \"original wording and intent” of the text to make the paper \"publishable and about feminism.\" An observant reader might ask: what could possibly remain of any Nazi content after that? But no one in the media, apparently, did.\"</p> <p>New Discourses, \"There Is No Good Part of Hitler's Mein Kampf\" <a href=\"https://newdiscourses.com/2021/03/there-is-no-good-part-of-hitlers-mein-kampf/\"> https://newdiscourses.com/2021/03/there-is-no-good-part-of-hitlers-mein-kampf/</a></p> <p>On this episode of the New Discourses Podcast, James Lindsay, who helped to write the paper and perpetrate the Grievance Studies Affair, talks about the project and the creation of this particular paper at unprecedented length and in unprecedented detail, revealing Nilssen not to know what he's talking about. If you have ever wondered about what the backstory of the creation of the “Feminist Mein Kampf” paper really was, including why its authors did it, you won't want to miss this long-form discussion and rare response to yet another underinformed critic of Lindsay, Boghossian, and Pluckrose's work.</p> <p>The Grieveance Studies Affair Revealed. <a href=\"https://www.youtube.com/watch?v=kVk9a5Jcd1k\">https://www.youtube.com/watch?v=kVk9a5Jcd1k</a></p> <p>Reviewer 1 Comments on Dog Park Paper</p> <p>\"page 9 - the human subjects are afforded anonymity and not asked about income, etc for ethical reasons. yet, the author as researcher intruded into the dogs' spaces to examine and record genitalia. I realize this was necessary to the project, but could the author acknowledge/explain/justify this (arguably, anthropocentric) difference? Indicating that it was necessary to the research would suffice but at least the difference should be acknowledged.\"</p> <p>Nestor de Buen, Anti-Science Humping in the Dog Park. <a href=\"https://conceptualdisinformation.substack.com/p/anti-science-humping-in-the-dog-park\"> https://conceptualdisinformation.substack.com/p/anti-science-humping-in-the-dog-park</a></p> <p>\"What is even more striking is that if the research had actually been conducted and the results showed what the paper says they show, there is absolutely no reason why it should not have been published. And moreover, what it proves is the opposite of what its intention is. It shows that one can make scientifically testable claims based on the conceptual framework of gender studies, and that the field has all the markings of a perfectly functional research programme.\"</p> <p>\"Yes, the dog park paper is based on false data and, like Sokal's, contains a lot of unnecessary jargon, but it is not nonsense, and the distinction is far from trivial. Nonsense implies one cannot even obtain a truth value from a proposition. In fact, the paper being false, if anything, proves that it is not nonsense, yet the grievance hoaxers try to pass falsity as nonsense. Nonsense is something like Chomsky's famous sentence “colorless green ideas sleep furiously.” It is nonsense because it is impossible to decide how one might evaluate whether it is true. A false sentence would be “the moon is cubical.” It has a definite meaning, it just happens not to be true.&nbsp;</p> <p>\"So, if the original Sokal Hoax is like Chomsky's sentence, the dog park paper is much more like “the moon is cubical.” And in fact, a more accurate analogy would be “the moon is cubical and here is a picture that proves it,” and an attached doctored picture of the cubical moon.\"</p> <p>Reviewer 2 Comments on the Dog-Park Paper</p> <p>\"I am a bit curious about your methodology. Can you say more? You describe your methods here (procedures for collecting data), but not really your overall approach to methodology. Did you just show up, observe, write copious notes, talk to people when necessary, and then leave? If so, it might be helpful to explicitly state this. It sounds to me like you did a kind of ethnography (methodology — maybe multispecies ethnography?) but that's not entirely clear here. Or are you drawing on qualitative methods in social behaviorism/symbolic interactionism? In either case, the methodology chosen should be a bit more clearly articulated.\"</p> <p>Counterweight. <a href=\"https://counterweightsupport.com/\">https://counterweightsupport.com/</a></p> <p>\"Welcome to Counterweight, the home of scholarship and advice on [Critical Social Justice](<a href=\"https://counterweightsupport.com/2021/02/17/what-do-we-mean-by-critical-social-justice/\">https://counterweightsupport.com/2021/02/17/what-do-we-mean-by-critical-social-justice/</a>) ideology. We are here to connect you with the resources, advice and guidance you need to address CSJ beliefs as you encounter them in your day-to-day life. The Counterweight community is a non-partisan, grassroots movement advocating for liberal concepts of social justice including individualism, universalism, viewpoint diversity and the free exchange of ideas. [Subscribe](https://counterweightsupport.com/subscribe-to-counterweight/) today to become part of the Counterweight movement.\"\"</p> <p>Inside Higher Ed, \"Blowback Against a Hoax.\" <a href=\"https://www.insidehighered.com/news/2019/01/08/author-recent-academic-hoax-faces-disciplinary-action-portland-state\"> https://www.insidehighered.com/news/2019/01/08/author-recent-academic-hoax-faces-disciplinary-action-portland-state</a></p> <p>Peter Boghossian Resignation Latter from PSU. <a href=\"https://bariweiss.substack.com/p/my-university-sacrificed-ideas-for\"> https://bariweiss.substack.com/p/my-university-sacrificed-ideas-for</a></p> <p>&nbsp;</p>"
    expected = "So, in rank defiance of our recent promise to 'get back to the nazis' instead we continue our James Lindsay coverage.\u{a0} (What... me? Irony? How dare you?)\u{a0} This time, Daniel patiently walks a distracted, slightly hyperactive, and increasingly incredulous Jack through the infamous 'Grievance Studies Hoax' (AKA 'Sokal Squared') in which Lindsay and colleagues Helen Pluckrose and Peter Boghossian tried (and then claimed) to prove something or other about modern Humanities academia by submitting a load of stupid fake papers to various feminist and fat studies journals.\u{a0} As Daniel reveals, the episode was an orgy of dishonesty and tactical point-missing that actually proved the opposite of what the team of snickering tricksters thought they were proving.\u{a0} Sadly, however, because we live in Hell, the trio have only raised their profiles as a result.\u{a0} A particular highlight of the episode is Lindsay revealing his staggering ignorance when 'responding' to criticism.\n\nContent warnings, as ever.\n\nPodcast Notes:\n\nPlease consider donating to help us make the show and stay independent.\u{a0} Patrons get exclusive access to one full extra episode a month.\n\nDaniel's Patreon: <a href=\"https://www.patreon.com/danielharper\">https://www.patreon.com/danielharper</a>\n\nJack's Patreon: <a href=\"https://www.patreon.com/user?u=4196618&amp;fan_landing=true\">https://www.patreon.com/user?u=4196618</a>\n\nIDSG Twitter: <a href=\"https://twitter.com/idsgpod\">https://twitter.com/idsgpod</a>\n\nDaniel's Twitter: <a href=\"https://twitter.com/danieleharper\">@danieleharper</a>\n\nJack's Twitter: <a href=\"https://twitter.com/_Jack_Graham_\">@_Jack_Graham_</a>\n\nIDSG on Apple Podcasts: <a href=\"https://podcasts.apple.com/us/podcast/i-dont-speak-german/id1449848509?ls=1\"> https://podcasts.apple.com/us/podcast/i-dont-speak-german/id1449848509?ls=1</a>\n\n\n\nShow Notes:\n\nJames Lindsay, New Discourses, \"Why You Can Be Transgender But Not Transracial.\"\" <a href=\"https://newdiscourses.com/2021/06/why-you-can-be-transgender-but-not-transracial/\"> https://newdiscourses.com/2021/06/why-you-can-be-transgender-but-not-transracial/</a>\n\nJames Lindsay has a day job, apparently. \"Maryville man walks path of healing and combat.\" <a href=\"https://www.thedailytimes.com/news/maryville-man-walks-path-of-healing-and-combat/article_5ea3c0ca-2e98-5283-9e59-06861b8588cb.html\"> https://www.thedailytimes.com/news/maryville-man-walks-path-of-healing-and-combat/article_5ea3c0ca-2e98-5283-9e59-06861b8588cb.html</a>\n\nAreo Magazine, Academic Grievance Studies and the Corruption of Scholarship. <a href=\"https://areomagazine.com/2018/10/02/academic-grievance-studies-and-the-corruption-of-scholarship/\"> https://areomagazine.com/2018/10/02/academic-grievance-studies-and-the-corruption-of-scholarship/</a>\n\nFull listing of Grievance Studies Papers and Reviews. <a href=\"https://drive.google.com/drive/folders/19tBy_fVlYIHTxxjuVMFxh4pqLHM_en18\"> https://drive.google.com/drive/folders/19tBy_fVlYIHTxxjuVMFxh4pqLHM_en18</a>\n\n'Mein Kampf' and the 'Feminazis': What Three Academics' Hitler Hoax Really Reveals About 'Wokeness'. <a href=\"https://web.archive.org/web/20210328112901/https://www.haaretz.com/us-news/.premium-hitler-hoax-academic-wokeness-culture-war-1.9629759\"> https://web.archive.org/web/20210328112901/https://www.haaretz.com/us-news/.premium-hitler-hoax-academic-wokeness-culture-war-1.9629759</a>\n\n\"First and foremost, the source material. The chapter the hoaxers chose, not by coincidence, one of the least ideological and racist parts of Hitler's book. Chapter 12, probably written in April/May 1925, deals with how the newly refounded NSDAP should rebuild as a party and amplify its program.\n\n\"According to their own account, the writers took parts of the chapter and inserted feminist \"buzzwords\"; they \"significantly changed\" the \"original wording and intent” of the text to make the paper \"publishable and about feminism.\" An observant reader might ask: what could possibly remain of any Nazi content after that? But no one in the media, apparently, did.\"\n\nNew Discourses, \"There Is No Good Part of Hitler's Mein Kampf\" <a href=\"https://newdiscourses.com/2021/03/there-is-no-good-part-of-hitlers-mein-kampf/\"> https://newdiscourses.com/2021/03/there-is-no-good-part-of-hitlers-mein-kampf/</a>\n\nOn this episode of the New Discourses Podcast, James Lindsay, who helped to write the paper and perpetrate the Grievance Studies Affair, talks about the project and the creation of this particular paper at unprecedented length and in unprecedented detail, revealing Nilssen not to know what he's talking about. If you have ever wondered about what the backstory of the creation of the “Feminist Mein Kampf” paper really was, including why its authors did it, you won't want to miss this long-form discussion and rare response to yet another underinformed critic of Lindsay, Boghossian, and Pluckrose's work.\n\nThe Grieveance Studies Affair Revealed. <a href=\"https://www.youtube.com/watch?v=kVk9a5Jcd1k\">https://www.youtube.com/watch?v=kVk9a5Jcd1k</a>\n\nReviewer 1 Comments on Dog Park Paper\n\n\"page 9 - the human subjects are afforded anonymity and not asked about income, etc for ethical reasons. yet, the author as researcher intruded into the dogs' spaces to examine and record genitalia. I realize this was necessary to the project, but could the author acknowledge/explain/justify this (arguably, anthropocentric) difference? Indicating that it was necessary to the research would suffice but at least the difference should be acknowledged.\"\n\nNestor de Buen, Anti-Science Humping in the Dog Park. <a href=\"https://conceptualdisinformation.substack.com/p/anti-science-humping-in-the-dog-park\"> https://conceptualdisinformation.substack.com/p/anti-science-humping-in-the-dog-park</a>\n\n\"What is even more striking is that if the research had actually been conducted and the results showed what the paper says they show, there is absolutely no reason why it should not have been published. And moreover, what it proves is the opposite of what its intention is. It shows that one can make scientifically testable claims based on the conceptual framework of gender studies, and that the field has all the markings of a perfectly functional research programme.\"\n\n\"Yes, the dog park paper is based on false data and, like Sokal's, contains a lot of unnecessary jargon, but it is not nonsense, and the distinction is far from trivial. Nonsense implies one cannot even obtain a truth value from a proposition. In fact, the paper being false, if anything, proves that it is not nonsense, yet the grievance hoaxers try to pass falsity as nonsense. Nonsense is something like Chomsky's famous sentence “colorless green ideas sleep furiously.” It is nonsense because it is impossible to decide how one might evaluate whether it is true. A false sentence would be “the moon is cubical.” It has a definite meaning, it just happens not to be true.\u{a0}\n\n\"So, if the original Sokal Hoax is like Chomsky's sentence, the dog park paper is much more like “the moon is cubical.” And in fact, a more accurate analogy would be “the moon is cubical and here is a picture that proves it,” and an attached doctored picture of the cubical moon.\"\n\nReviewer 2 Comments on the Dog-Park Paper\n\n\"I am a bit curious about your methodology. Can you say more? You describe your methods here (procedures for collecting data), but not really your overall approach to methodology. Did you just show up, observe, write copious notes, talk to people when necessary, and then leave? If so, it might be helpful to explicitly state this. It sounds to me like you did a kind of ethnography (methodology — maybe multispecies ethnography?) but that's not entirely clear here. Or are you drawing on qualitative methods in social behaviorism/symbolic interactionism? In either case, the methodology chosen should be a bit more clearly articulated.\"\n\nCounterweight. <a href=\"https://counterweightsupport.com/\">https://counterweightsupport.com/</a>\n\n\"Welcome to Counterweight, the home of scholarship and advice on [Critical Social Justice](<a href=\"https://counterweightsupport.com/2021/02/17/what-do-we-mean-by-critical-social-justice/\">https://counterweightsupport.com/2021/02/17/what-do-we-mean-by-critical-social-justice/</a>) ideology. We are here to connect you with the resources, advice and guidance you need to address CSJ beliefs as you encounter them in your day-to-day life. The Counterweight community is a non-partisan, grassroots movement advocating for liberal concepts of social justice including individualism, universalism, viewpoint diversity and the free exchange of ideas. [Subscribe](<a href=\"https://counterweightsupport.com/subscribe-to-counterweight/\">https://counterweightsupport.com/subscribe-to-counterweight/</a>) today to become part of the Counterweight movement.\"\"\n\nInside Higher Ed, \"Blowback Against a Hoax.\" <a href=\"https://www.insidehighered.com/news/2019/01/08/author-recent-academic-hoax-faces-disciplinary-action-portland-state\"> https://www.insidehighered.com/news/2019/01/08/author-recent-academic-hoax-faces-disciplinary-action-portland-state</a>\n\nPeter Boghossian Resignation Latter from PSU. <a href=\"https://bariweiss.substack.com/p/my-university-sacrificed-ideas-for\"> https://bariweiss.substack.com/p/my-university-sacrificed-ideas-for</a>\n\n\n\n"

    expect(markup_for(description)).to eq(expected)
  end

  # fn test_newline_based
  it "test_newline_based" do
    description = "Also available in video form at https://youtu.be/NUPWY_evu30\n" \
      "\n" \
      "In a recent view by Contrapoints, she goes over her account of envy and its connection with online politics. In doing so she utilizes Nietzsche (alongside a critique of Nietzsche). How accurate is this account to Nietzsche's work and where does it go wrong?  \n" \
      "\n" \
      "Thank you to We're in Hell, BadEmpanada, and Chelsea Manning for the voice lines! \n" \
      "\n" \
      "Edited by Lexi Fontaine: https://twitter.com/softgothoutlaw \n" \
      "\n" \
      "Music by Alex Ballantyne: https://transistorriot.bandcamp.com \n" \
      "\n" \
      "This was an early release to my patrons at https://pateron.com/livagar \n" \
      "\n" \
      "Watch me stream on twitch at https://twitch.tv/livagar \n" \
      "\n" \
      "All of my links at https:// livagar.com"

    expected = "Also available in video form at <a href=\"https://youtu.be/NUPWY_evu30\">https://youtu.be/NUPWY_evu30</a>\n" \
      "\n" \
      "In a recent view by Contrapoints, she goes over her account of envy and its connection with online politics. In doing so she utilizes Nietzsche (alongside a critique of Nietzsche). How accurate is this account to Nietzsche's work and where does it go wrong? \n" \
      "\n" \
      "Thank you to We're in Hell, BadEmpanada, and Chelsea Manning for the voice lines! \n" \
      "\n" \
      "Edited by Lexi Fontaine: <a href=\"https://twitter.com/softgothoutlaw\">https://twitter.com/softgothoutlaw</a> \n" \
      "\n" \
      "Music by Alex Ballantyne: <a href=\"https://transistorriot.bandcamp.com\">https://transistorriot.bandcamp.com</a> \n" \
      "\n" \
      "This was an early release to my patrons at <a href=\"https://pateron.com/livagar\">https://pateron.com/livagar</a> \n" \
      "\n" \
      "Watch me stream on twitch at <a href=\"https://twitch.tv/livagar\">https://twitch.tv/livagar</a> \n" \
      "\n" \
      "All of my links at https:// <a href=\"https:livagar.com\">livagar.com</a>"

    expect(markup_for(description)).to eq(expected)
  end

  # fn test_newline_based2
  it "test_newline_based2" do
    description = "We’re back to a normal-style ep after a week of interviews. We’re taking a look at the fast-tracked aid package to intelligence agents suffering unreality issues, the Biden administration addressing just the optics at the border, and AOC addressing just the optics of the Iron Dome bill. Finally, we having a reading series that functions as a bit of a coda to Will and Matt’s visit to Ozy Fest way back in 2018.\n\nOne last time, go subscribe to https://www.youtube.com/chapotraphouse\n\nAnd go grab some of Simon Roy’s great posters over at https://shop.chapotraphouse.com/\nMore merch coming soon!"
    expected = "We’re back to a normal-style ep after a week of interviews. We’re taking a look at the fast-tracked aid package to intelligence agents suffering unreality issues, the Biden administration addressing just the optics at the border, and AOC addressing just the optics of the Iron Dome bill. Finally, we having a reading series that functions as a bit of a coda to Will and Matt’s visit to Ozy Fest way back in 2018.\n\nOne last time, go subscribe to <a href=\"https://www.youtube.com/chapotraphouse\">https://www.youtube.com/chapotraphouse</a>\n\nAnd go grab some of Simon Roy’s great posters over at <a href=\"https://shop.chapotraphouse.com/\">https://shop.chapotraphouse.com/</a>\nMore merch coming soon!"

    expect(markup_for(description)).to eq(expected)
  end

  # fn test_list_ordered
  it "test_list_ordered" do
    description = "<ol><li>first</li><li>second</li><li>third</li></ol>"
    expected = "\n    1. first\n    2. second\n    3. third\n\n"

    expect(markup_for(description)).to eq(expected)
  end

  # fn test_list_unordered
  it "test_list_unordered" do
    description = "<ul><li>first</li><li>second</li><li>third</li></ul>"
    expected = "\n    • first\n    • second\n    • third\n\n"

    expect(markup_for(description)).to eq(expected)
  end

  # fn test_list_ordered_nested
  it "test_list_ordered_nested" do
    description = "<ol><li>first</li><li>second<ol><li> sub list first</li><li> sub list second</li></li></ol><li>third</li></ol>"
    expected = "\n    1. first\n    2. second\n        1. sub list first\n        2. sub list second\n\n\n    3. third\n\n"

    expect(markup_for(description)).to eq(expected)
  end

  # fn test_timecode
  it "test_timecode" do
    description = "<ul>" \
      "<li>Twitter: <a href=\"https://twitter.com/rustaceanfm\">@rustaceanfm</a></li>" \
      "<li>Discord: <a href=\"https://discord.gg/cHc3Gyc\">Rustacean Station</a></li>" \
      "<li>Github: <a href=\"https://github.com/rustacean-station/\">@rustacean-station</a></li>" \
      "<li>Email: <a href=\"mailto:hello@rustacean-station.org\">hello@rustacean-station.org</a></li>" \
      "</ul>" \
      "<h2 id=\"timestamps\">Timestamps</h2>" \
      "<ul>" \
      "<li>[@0:33] - Daniel’s introduction</li>" \
      "<li>[@3:38] - Tauri’s focus on safety and security</li>" \
      "<li>[@6:50] - Tauri’s mission to reduce their footprint</li>" \
      "<li>[@14:48] - How does Tauri handles features that are not supported across different platforms</li>" \
      "<li>[@23:56] - How does Tauri monetize to keep the project going?</li>" \
      "<li>[@26:16] - Why choose Tauri over other solutions?</li>" \
      "<li>[@28:57] - What are the tools being built with Tauri?</li>" \
      "<li>[@31:09] - Tyler’s programming background</li>" \
      "<li>[@35:11] - Tauri’s future release and features</li>" \
      "<li>[@38:38] - ‘Tauri Foundations’ book by Daniel Thompson-Yvetot and Lucas Nogueira</li>" \
      "<li>[@40:00] - Requirement on building a Tauri app</li>" \
      "<li>[@43:13] - Parting thoughts</li>" \
      "</ul>"

    expected = "\n" \
      "    • Twitter: <a href=\"https://twitter.com/rustaceanfm\">@rustaceanfm</a>\n" \
      "    • Discord: <a href=\"https://discord.gg/cHc3Gyc\">Rustacean Station</a>\n" \
      "    • Github: <a href=\"https://github.com/rustacean-station/\">@rustacean-station</a>\n" \
      "    • Email: <a href=\"mailto:hello@rustacean-station.org\">hello@rustacean-station.org</a>\n" \
      "\n" \
      "Timestamps\n" \
      "    • [@<a href=\"jump:33\" title=\"Jump to 00:33\">0:33</a>] - Daniel’s introduction\n" \
      "    • [@<a href=\"jump:218\" title=\"Jump to 03:38\">3:38</a>] - Tauri’s focus on safety and security\n" \
      "    • [@<a href=\"jump:410\" title=\"Jump to 06:50\">6:50</a>] - Tauri’s mission to reduce their footprint\n" \
      "    • [@<a href=\"jump:888\" title=\"Jump to 14:48\">14:48</a>] - How does Tauri handles features that are not supported across different platforms\n" \
      "    • [@<a href=\"jump:1436\" title=\"Jump to 23:56\">23:56</a>] - How does Tauri monetize to keep the project going?\n" \
      "    • [@<a href=\"jump:1576\" title=\"Jump to 26:16\">26:16</a>] - Why choose Tauri over other solutions?\n" \
      "    • [@<a href=\"jump:1737\" title=\"Jump to 28:57\">28:57</a>] - What are the tools being built with Tauri?\n" \
      "    • [@<a href=\"jump:1869\" title=\"Jump to 31:09\">31:09</a>] - Tyler’s programming background\n" \
      "    • [@<a href=\"jump:2111\" title=\"Jump to 35:11\">35:11</a>] - Tauri’s future release and features\n" \
      "    • [@<a href=\"jump:2318\" title=\"Jump to 38:38\">38:38</a>] - ‘Tauri Foundations’ book by Daniel Thompson-Yvetot and Lucas Nogueira\n" \
      "    • [@<a href=\"jump:2400\" title=\"Jump to 40:00\">40:00</a>] - Requirement on building a Tauri app\n" \
      "    • [@<a href=\"jump:2593\" title=\"Jump to 43:13\">43:13</a>] - Parting thoughts\n" \
      "\n"

    expect(markup_for(description)).to eq(expected)
  end

  # fn test_escape_lt_gt_and_img
  it "test_escape_lt_gt_and_img" do
    description = "<p>" \
      "<a href=\"http://faif.us/cast-media/FaiF_FOSSY-2023.ogg\"><img alt=\"[Direct download of cast in Ogg/Vorbis\n" \
      "                                          format]\" src=\"http://faif.us/img/cast/audio_ogg_button.png\"></a>\n" \
      "<a href=\"http://faif.us/cast-media/FaiF_FOSSY-2023.mp3\"><img alt=\"[Direct download of cast in MP3 format]\" src=\"http://faif.us/img/cast/audio_mp3_button.png\"></a>\n" \
      "</p>\n" \
      "<p>\n" \
      "Come to <a href=\"https://2023.fossy.us/\">FOSSY 2023</a>!\n" \
      "</p>\n" \
      "<h3>Show Notes:</h3>\n" \
      "\n" \
      "<a href=\"https://2023.fossy.us/\">FOSSY 2023</a> will happen next week in Portland, OR, USA.\n" \
      "\n" \
      "<hr width=\"80%\">\n" \
      "\n" \
      "<p>Send feedback and comments on the cast\n" \
      "to <a href=\"mailto:cast@faif.us\">&lt;oggcast@faif.us&gt;</a>.\n" \
      "You can keep in touch with <a href=\"http://faif.us\">Free as in Freedom</a>\n" \
      "  by <a href=\"https://twitter.com/conservancy\">following Conservancy on\n" \
      "    on Twitter</a> and <a href=\"https://twitter.com/faifcast\">and FaiF on Twitter</a>.  We are working on setting up a group chat again, too!</p>\n" \
      "\n" \
      "<p>Free as in Freedom is produced by <a href=\"http://danlynch.org/blog/\">Dan Lynch</a>\n" \
      "  of <a href=\"http://danlynch.org/\">danlynch.org</a>.\n" \
      "Theme\n" \
      "  music written and performed\n" \
      "  by <a href=\"http://www.miketarantino.com\">Mike Tarantino</a>\n" \
      "  with <a href=\"http://www.charliepaxson.com\">Charlie Paxson</a> on drums.</p>\n" \
      "\n" \
      "<p><a href=\"https://creativecommons.org/licenses/by-sa/4.0/\"><img alt=\"Creative Commons License\" src=\"http://i.creativecommons.org/l/by-sa/4.0/88x31.png\"></a>\n" \
      "   The content\n" \
      "   of <span>this\n" \
      "   audcast</span>, and the accompanying show notes and music are licensed\n" \
      "   under the <a href=\"https://creativecommons.org/licenses/by-sa/4.0/\">Creative\n" \
      "   Commons Attribution-Share-Alike 4.0 license (CC BY-SA 4.0)</a>.\n" \
      "   </p>"

    expected = "<a href=\"http://faif.us/cast-media/FaiF_FOSSY-2023.ogg\">[[Direct download of cast in Ogg/Vorbis format]]\n" \
      "</a><a href=\"http://faif.us/cast-media/FaiF_FOSSY-2023.mp3\">[[Direct download of cast in MP3 format]]\n" \
      "</a>\n" \
      "\n" \
      "Come to <a href=\"https://2023.fossy.us/\">FOSSY 2023</a>! \n" \
      "\n" \
      "Show Notes: <a href=\"https://2023.fossy.us/\">FOSSY 2023</a> will happen next week in Portland, OR, USA.  Send feedback and comments on the cast to <a href=\"mailto:cast@faif.us\">&lt;oggcast@faif.us&gt;</a>. You can keep in touch with <a href=\"http://faif.us\">Free as in Freedom</a> by <a href=\"https://twitter.com/conservancy\">following Conservancy on on Twitter</a> and <a href=\"https://twitter.com/faifcast\">and FaiF on Twitter</a>. We are working on setting up a group chat again, too!\n" \
      "\n" \
      "Free as in Freedom is produced by <a href=\"http://danlynch.org/blog/\">Dan Lynch</a> of <a href=\"http://danlynch.org/\">danlynch.org</a>. Theme music written and performed by <a href=\"http://www.miketarantino.com\">Mike Tarantino</a> with <a href=\"http://www.charliepaxson.com\">Charlie Paxson</a> on drums.\n" \
      "\n" \
      "<a href=\"https://creativecommons.org/licenses/by-sa/4.0/\">[Creative Commons License]\n" \
      "</a>The content of this audcast, and the accompanying show notes and music are licensed under the <a href=\"https://creativecommons.org/licenses/by-sa/4.0/\">Creative Commons Attribution-Share-Alike 4.0 license (CC BY-SA 4.0)</a>. \n\n"

    expect(markup_for(description)).to eq(expected)
  end

  # fn test_hash_invalid_link
  it "test_hash_invalid_link" do
    description = '<p><a href=" #whatever">🤷</a></p>'
    expected = "🤷\n\n"

    expect(markup_for(description)).to eq(expected)
  end

  # fn test_empty_link
  it "test_empty_link" do
    description = '<p><a href="">🤷</a></p>'
    expected = "🤷\n\n"

    expect(markup_for(description)).to eq(expected)
  end

  # fn test_hash_timestamp_link
  it "test_hash_timestamp_link" do
    description = '<p><a href="#t=13:12">13:12</a></p>'
    expected = "<a href=\"jump:792\" title=\"Jump to 13:12\">13:12</a>\n\n"

    expect(markup_for(description)).to eq(expected)
  end

  # fn test_do_not_double_escape_sequences
  it "test_do_not_double_escape_sequences" do
    description = "Will &amp; Felix catch up on Democrats’ commitment to burning millions of dollars in search of a crumb of clout from the pod-mano-sphere, and John Fetterman’s chronic senate absenteeism as he searches for good vibes. Then, we’re joined by Lever News’ David Sirota &amp; Arjun Singh to discuss their new podcast series Tax Revolt &amp; the “Big Beautiful Bill” working its way through congress. We look at the devastating consequences of GOP tax policies, the increasing unpopularity of such drastic cuts, and how they fit in with the 50 year conservative war against taxes.\n\nFind all things Lever News at: https://www.levernews.com/\n\nAnd listen to Tax Revolt here or wherever you get pods: https://the.levernews.com/tax-revolt/"
    expected = "Will &amp; Felix catch up on Democrats’ commitment to burning millions of dollars in search of a crumb of clout from the pod-mano-sphere, and John Fetterman’s chronic senate absenteeism as he searches for good vibes. Then, we’re joined by Lever News’ David Sirota &amp; Arjun Singh to discuss their new podcast series Tax Revolt &amp; the “Big Beautiful Bill” working its way through congress. We look at the devastating consequences of GOP tax policies, the increasing unpopularity of such drastic cuts, and how they fit in with the 50 year conservative war against taxes.\n\nFind all things Lever News at: <a href=\"https://www.levernews.com/\">https://www.levernews.com/</a>\n\nAnd listen to Tax Revolt here or wherever you get pods: <a href=\"https://the.levernews.com/tax-revolt/\">https://the.levernews.com/tax-revolt/</a>"

    expect(markup_for(description)).to eq(expected)
  end
end
