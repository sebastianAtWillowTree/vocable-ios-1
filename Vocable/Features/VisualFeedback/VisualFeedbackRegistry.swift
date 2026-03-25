//
//  VisualFeedbackRegistry.swift
//  Vocable
//
//  Copyright © 2025 WillowTree. All rights reserved.
//

import UIKit

/// Maps `Phrase.identifier` values to visual feedback content for bundled preset phrases.
enum VisualFeedbackRegistry {

    static func content(for phraseIdentifier: String) -> AnyVisualFeedbackContent? {
        if #available(iOS 17.0, *) {
            return phraseMapping[phraseIdentifier]
        }
        return nil
    }

    @available(iOS 17.0, *)
    private static func sf(
        _ name: String,
        _ kind: SFSymbolFeedbackContent.SymbolAnimationKind,
        _ tint: UIColor
    ) -> AnyVisualFeedbackContent {
        AnyVisualFeedbackContent(
            SFSymbolFeedbackContent(symbolName: name, animationKind: kind, tintColor: tint)
        )
    }

    @available(iOS 17.0, *)
    private static let phraseMapping: [String: AnyVisualFeedbackContent] = {

        var map: [String: AnyVisualFeedbackContent] = [:]

        // MARK: Kids (child-focused examples: swing, more, go, …)
        map["preset_A1F00001-0001-4000-8000-000000000001"] = sf("figure.play", .bounce, .systemBlue)
        map["preset_A1F00001-0002-4000-8000-000000000002"] = sf("plus.circle.fill", .bounce, .systemGreen)
        map["preset_A1F00001-0003-4000-8000-000000000003"] = sf("arrow.right.circle.fill", .pulse, .systemOrange)
        map["preset_A1F00001-0004-4000-8000-000000000004"] = sf("play.circle.fill", .bounce, .systemGreen)
        map["preset_A1F00001-0005-4000-8000-000000000005"] = sf("stop.circle.fill", .pulse, .systemRed)
        map["preset_A1F00001-0006-4000-8000-000000000006"] = sf("questionmark.circle.fill", .bounce, .systemYellow)
        map["preset_A1F00001-0007-4000-8000-000000000007"] = sf("hand.point.up.left.fill", .bounce, .systemBlue)
        map["preset_A1F00001-0008-4000-8000-000000000008"] = sf("checkmark.circle.fill", .bounce, .systemGreen)
        map["preset_A1F00001-0009-4000-8000-000000000009"] = sf("person.fill.checkmark", .bounce, .systemTeal)
        map["preset_A1F00001-000A-4000-8000-00000000000A"] = sf("leaf.fill", .bounce, .systemGreen)
        map["preset_A1F00001-000B-4000-8000-00000000000B"] = sf("figure.2.and.child.holdinghands", .bounce, .systemPink)
        map["preset_A1F00001-000C-4000-8000-00000000000C"] = sf("book.fill", .bounce, .systemIndigo)

        // MARK: Basic Needs
        map["preset_7ACA0926-DB7F-4B9E-872C-AE9690AD79E7"] = sf("toilet.fill", .bounce, .systemBlue)
        map["preset_9DEB32B5-8606-4689-8F6A-0B251F4DB377"] = sf("drop.fill", .pulse, .systemCyan)
        map["preset_E012D902-E8BA-4BEA-92C7-7107ECF8051C"] = sf("fork.knife", .bounce, .systemOrange)
        map["preset_8C4D0099-9BA8-4914-A6B5-730FFDC8C499"] = sf("snowflake", .pulse, .systemCyan)
        map["preset_6AD93FB9-437C-455F-A4AF-C96033BCBCAE"] = sf("sun.max.fill", .pulse, .systemRed)
        map["preset_F6F03BBD-B9CD-41F5-B26A-FCC13CCBB199"] = sf("moon.zzz.fill", .pulse, .systemIndigo)
        map["preset_ADDD57C6-D11E-4B32-A2B3-05AA43D9AC8C"] = sf("hand.thumbsup.fill", .bounce, .systemGreen)
        map["preset_C6C14627-E48E-4EF3-B81D-64C191F2EC75"] = sf("face.smiling.fill", .bounce, .systemGreen)
        map["preset_C6E6B6E7-BEB6-466D-822A-F8CE2D092B9E"] = sf("exclamationmark.triangle.fill", .pulse, .systemOrange)
        map["preset_5542BE2F-419E-41A5-BBF2-5B82E0A49834"] = sf("bolt.heart.fill", .pulse, .systemRed)
        map["preset_28A8F6B6-E196-4981-B762-652C288A0C29"] = sf("checkmark.circle.fill", .bounce, .systemGreen)
        map["preset_0B491C3E-1A7F-4A94-A523-6DE329BF9E72"] = sf("bed.double.fill", .bounce, .systemIndigo)
        map["preset_BBE8BABC-CCBF-49BF-87D4-057016AADBC5"] = sf("figure.stand", .bounce, .systemTeal)

        // MARK: Conversation
        map["preset_3EF1FBFA-E07A-47B5-BDF6-3AE7A684B834"] = sf("hand.wave.fill", .bounce, .systemYellow)
        map["preset_9929E83B-997D-40AA-841C-130709F5115B"] = sf("sunrise.fill", .bounce, .systemOrange)
        map["preset_D6A67E02-3D07-4D44-8B04-2C1B9B8B167E"] = sf("sunset.fill", .bounce, .systemPurple)
        map["preset_0EE14D06-92D7-4A26-A15F-253528F14A69"] = sf("person.2.fill", .bounce, .systemBlue)
        map["preset_0EF33A3F-41E8-4E47-9B2C-69FC86B957FC"] = sf("questionmark.bubble.fill", .pulse, .systemBlue)
        map["preset_1B634A96-563E-4275-875A-2B705A5D1178"] = sf("questionmark.bubble.fill", .pulse, .systemBlue)
        map["preset_31E8760F-E728-4261-A82E-B50AB40C73FF"] = sf("questionmark.bubble.fill", .pulse, .systemTeal)
        map["preset_24B48F19-EA3A-49A1-88C1-AACB67FE7278"] = sf("questionmark.bubble.fill", .pulse, .systemTeal)
        map["preset_B2442AA0-6004-4636-9B39-2DB97ADD1DA1"] = sf("hand.wave.fill", .bounce, .systemBlue)
        map["preset_045EF309-3EB7-46B9-8AB7-31BC8482E3DC"] = sf("hand.thumbsup.fill", .bounce, .systemGreen)
        map["preset_573DD827-7201-49F1-8BE8-0BC18028A8CB"] = sf("hand.thumbsdown.fill", .bounce, .systemRed)
        map["preset_D64EE532-14D3-4434-B671-8F4368EC0A8D"] = sf("hand.thumbsup.fill", .bounce, .systemGreen)
        map["preset_6B463AF1-C884-45CD-9194-90806E75FD70"] = sf("lightbulb.fill", .bounce, .systemYellow)
        map["preset_A436EAAF-BD8A-4D8D-81EA-DC6D3C849D4A"] = sf("heart.fill", .bounce, .systemPink)
        map["preset_A02D6604-5C7C-4BB0-8C4A-E1C5E0D1A869"] = sf("hand.raised.fill", .pulse, .systemRed)
        map["preset_30153E11-D48C-47C8-9186-47988D0A5B7A"] = sf("xmark.circle.fill", .bounce, .systemRed)
        map["preset_A74483A8-4069-40D7-992C-01295934E97C"] = sf("arrow.clockwise.circle.fill", .bounce, .systemBlue)

        // MARK: General
        map["preset_33B3F4B7-2438-439B-A21B-46D2599C8840"] = sf("hands.sparkles", .bounce, .systemYellow)
        map["preset_72633C5C-47A2-4D5E-9615-E1408234478F"] = sf("heart.fill", .bounce, .systemPink)
        map["preset_8BCBACFB-D5ED-46CB-B3E2-21FB31D8D6AD"] = sf("checkmark.circle.fill", .bounce, .systemGreen)
        map["preset_FABE749C-B54D-4031-B8E7-62777B34D273"] = sf("xmark.circle.fill", .bounce, .systemRed)
        map["preset_DFB79E0D-CF93-4744-B9EE-12738E1864E2"] = sf("questionmark.circle.fill", .pulse, .systemOrange)
        map["preset_7FF4503F-F838-48BE-B529-758B3531093C"] = sf("clock.fill", .pulse, .systemBlue)
        map["preset_6CBD6D3E-42A7-435C-B661-2ABD669DC6BE"] = sf("questionmark.circle.fill", .pulse, .systemGray)
        map["preset_BEE6FF86-CE30-4096-9E37-C469F63630B7"] = sf("arrow.uturn.backward.circle.fill", .bounce, .systemOrange)
        map["preset_63980C93-EE77-40DE-BDE7-BF8F97EC0304"] = sf("clock.fill", .pulse, .systemBlue)

        // MARK: Environment
        map["preset_9E3230D7-1172-491A-8A00-E734B1661DC1"] = sf("lightbulb.fill", .bounce, .systemYellow)
        map["preset_46EF7041-50F7-4B64-A0F6-879A8A3D7532"] = sf("lightbulb.slash.fill", .bounce, .systemGray)
        map["preset_9A808275-0D67-49E4-8BF8-6F22A0C7E169"] = sf("person.slash", .bounce, .systemRed)
        map["preset_E7D11E13-BC4F-4FE5-9C8A-BE2DE31AEE7F"] = sf("person.2.fill", .bounce, .systemGreen)
        map["preset_30474911-619F-4FBF-B7DA-F64039F556F2"] = sf("speaker.slash.fill", .bounce, .systemGray)
        map["preset_0167AA43-587D-436F-91A9-9CEEAF1CCCF1"] = sf("bubble.left.fill", .bounce, .systemBlue)
        map["preset_FB19C160-BC96-4580-9542-6F54AA1B2D70"] = sf("tv.fill", .bounce, .systemBlue)
        map["preset_9EE3A781-E84E-4728-976F-8EF993B8174C"] = sf("tv.slash", .bounce, .systemGray)
        map["preset_DC942BB6-B2BF-4ABB-8931-719BD2A504E6"] = sf("speaker.wave.3.fill", .pulse, .systemBlue)
        map["preset_702D3BAD-6C56-4DC6-8290-8E0693B63152"] = sf("speaker.wave.1.fill", .pulse, .systemOrange)
        map["preset_42DC7273-92F9-4149-8166-966C3C201862"] = sf("sun.max.fill", .bounce, .systemYellow)
        map["preset_88556B8E-FE61-401D-888C-0D79568715A0"] = sf("moon.fill", .bounce, .systemGray)
        map["preset_2BF1A363-CE24-4F26-9727-C5EAD1FEC27C"] = sf("window.vertical", .bounce, .systemTeal)
        map["preset_C865BE96-40B5-406C-9BAA-0A0D3280E377"] = sf("window.vertical", .bounce, .systemGray)

        // MARK: Personal Care
        map["preset_1244394F-2793-47EF-BCAC-DB8BBDAB78C6"] = sf("pills.fill", .bounce, .systemPurple)
        map["preset_64348AD1-9F63-4ADA-B391-E1742913C0E6"] = sf("bathtub.fill", .bounce, .systemCyan)
        map["preset_81B473E3-2FC9-40F0-AE59-3C658EC6CD91"] = sf("shower.fill", .bounce, .systemCyan)
        map["preset_73B654AA-C999-4864-BF5A-77379DAA991C"] = sf("drop.triangle.fill", .bounce, .systemCyan)
        map["preset_1BAD392A-C26C-4080-B0F2-FC544E08349C"] = sf("paintbrush.pointed.fill", .bounce, .systemBrown)
        map["preset_4F776A4A-4154-4DFE-89AC-E603C2A578EE"] = sf("bed.double.fill", .bounce, .systemIndigo)
        map["preset_8359B09D-7259-40CC-B258-02895ECC4DB7"] = sf("mouth", .bounce, .systemTeal)
        map["preset_939B4829-D8B4-42F1-B8A2-0E956AAE1FEE"] = sf("waveform.path.ecg", .pulse, .systemRed)
        map["preset_05754D0C-962D-48C3-8554-E4F7D5E86D93"] = sf("tshirt.fill", .bounce, .systemBrown)

        return map
    }()
}
