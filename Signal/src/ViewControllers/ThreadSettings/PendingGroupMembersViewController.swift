//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

protocol PendingGroupMembersViewControllerDelegate: class {
    func pendingGroupMembersViewDidUpdate()
}

// MARK: -

@objc
public class PendingGroupMembersViewController: OWSTableViewController {

    // MARK: - Dependencies

    fileprivate var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    fileprivate var tsAccountManager: TSAccountManager {
        return .sharedInstance()
    }

    private var contactsManager: OWSContactsManager {
        return Environment.shared.contactsManager
    }

    // MARK: -

    weak var pendingGroupMembersViewControllerDelegate: PendingGroupMembersViewControllerDelegate?

    private var groupModel: TSGroupModel

    private let groupViewHelper: GroupViewHelper

    required init(groupModel: TSGroupModel, groupViewHelper: GroupViewHelper) {
        self.groupModel = groupModel
        self.groupViewHelper = groupViewHelper

        super.init()
    }

    // MARK: - View Lifecycle

    @objc
    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("PENDING_GROUP_MEMBERS_VIEW_TITLE",
                                  comment: "The title for the 'pending group members' view.")

        self.useThemeBackgroundColors = true

        updateTableContents()
    }

    // MARK: -

    private func updateTableContents() {
        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("missing local address")
            return
        }

        let contents = OWSTableContents()

        let groupMembership = groupModel.groupMembership
        let allPendingMembersSorted = databaseStorage.uiRead { transaction in
            self.contactsManager.sortSignalServiceAddresses(Array(groupMembership.pendingMembers),
                                                            transaction: transaction)
        }

        // Note that these collections retain their sorting from above.
        var membersInvitedByLocalUser = [SignalServiceAddress]()
        var membersInvitedByOtherUsers = [SignalServiceAddress: [SignalServiceAddress]]()
        for invitedAddress in allPendingMembersSorted {
            guard let inviterUuid = groupMembership.addedByUuid(forPendingMember: invitedAddress) else {
                owsFailDebug("Missing inviter.")
                continue
            }
            let inviterAddress = SignalServiceAddress(uuid: inviterUuid)
            if inviterAddress == localAddress {
                membersInvitedByLocalUser.append(invitedAddress)
            } else {
                var invitedMembers: [SignalServiceAddress] = membersInvitedByOtherUsers[inviterAddress] ?? []
                invitedMembers.append(invitedAddress)
                membersInvitedByOtherUsers[inviterAddress] = invitedMembers
            }
        }

        let localSection = OWSTableSection()
        localSection.headerTitle = NSLocalizedString("PENDING_GROUP_MEMBERS_SECTION_TITLE_PEOPLE_YOU_INVITED",
                                                     comment: "Title for the 'people you invited' section of the 'pending group members' view.")
        let canRevoke = groupViewHelper.canEditConversationMembership
        if membersInvitedByLocalUser.count > 0 {
            for address in membersInvitedByLocalUser {
                localSection.add(OWSTableItem(customCellBlock: {
                    let cell = ContactTableViewCell()
                    cell.selectionStyle = canRevoke ? .default : .none
                    cell.configure(withRecipientAddress: address)
                    return cell
                },
                                              customRowHeight: UITableView.automaticDimension) { [weak self] in
                                                if canRevoke {
                                                    self?.showRevokePendingInviteFromLocalUserConfirmation(invitedAddress: address)
                                                }
                })
            }
        } else {
            localSection.add(OWSTableItem.softCenterLabel(withText: NSLocalizedString("PENDING_GROUP_MEMBERS_NO_PENDING_MEMBERS",
                                                                                 comment: "Label indicating that a group has no pending members."),
                                                     customRowHeight: UITableView.automaticDimension))
        }
        contents.addSection(localSection)

        let otherUsersSection = OWSTableSection()
        otherUsersSection.headerTitle = NSLocalizedString("PENDING_GROUP_MEMBERS_SECTION_TITLE_INVITES_FROM_OTHER_MEMBERS",
                                                          comment: "Title for the 'invites by other group members' section of the 'pending group members' view.")
        otherUsersSection.footerTitle = NSLocalizedString("PENDING_GROUP_MEMBERS_SECTION_FOOTER_INVITES_FROM_OTHER_MEMBERS",
                                                          comment: "Footer for the 'invites by other group members' section of the 'pending group members' view.")

        if membersInvitedByOtherUsers.count > 0 {
            let inviterAddresses = databaseStorage.uiRead { transaction in
                self.contactsManager.sortSignalServiceAddresses(Array(membersInvitedByOtherUsers.keys),
                                                                transaction: transaction)
            }
            for inviterAddress in inviterAddresses {
                guard let invitedAddresses = membersInvitedByOtherUsers[inviterAddress] else {
                    owsFailDebug("Missing invited addresses.")
                    continue
                }

                otherUsersSection.add(OWSTableItem(customCellBlock: { [weak self] in
                    guard let self = self else {
                        owsFailDebug("Missing self")
                        return OWSTableItem.newCell()
                    }

                    let cell = ContactTableViewCell()

                    cell.selectionStyle = .none

                    let inviterName = self.contactsManager.displayName(for: inviterAddress)
                    let customName: String
                    if inviterAddresses.count > 1 {
                        let format = NSLocalizedString("PENDING_GROUP_MEMBERS_MEMBER_INVITED_N_USERS_FORMAT",
                                                       comment: "Format for label indicating the a group member has invited N other users to the group. Embeds {{ %1$@ name of the inviting group member, %2$@ the number of users they have invited. }}.")
                        customName = String(format: format, inviterName, OWSFormat.formatInt(inviterAddresses.count))
                    } else {
                        let format = NSLocalizedString("PENDING_GROUP_MEMBERS_MEMBER_INVITED_1_USER_FORMAT",
                                                       comment: "Format for label indicating the a group member has invited 1 other user to the group. Embeds {{ the name of the inviting group member. }}.")
                        customName = String(format: format, inviterName, OWSFormat.formatInt(inviterAddresses.count))
                    }
                    cell.setCustomName(customName)

                    cell.configure(withRecipientAddress: inviterAddress)

                    return cell
                    },
                                                   customRowHeight: UITableView.automaticDimension) { [weak self] in
                                                    if canRevoke {
                                                        self?.showRevokePendingInviteFromOtherUserConfirmation(invitedAddresses: invitedAddresses,
                                                                                                               inviterAddress: inviterAddress)
                                                    }
                })
            }
        } else {
            otherUsersSection.add(OWSTableItem.softCenterLabel(withText: NSLocalizedString("PENDING_GROUP_MEMBERS_NO_PENDING_MEMBERS",
                                                                                           comment: "Label indicating that a group has no pending members."),
                                                               customRowHeight: UITableView.automaticDimension))
        }
        contents.addSection(otherUsersSection)

        self.contents = contents
    }

    fileprivate func reloadGroupModelAndTableContents() {
        pendingGroupMembersViewControllerDelegate?.pendingGroupMembersViewDidUpdate()

        guard let newModel = (databaseStorage.uiRead { (transaction) -> TSGroupModel? in
            guard let groupThread = TSGroupThread.fetch(groupId: self.groupModel.groupId, transaction: transaction) else {
                owsFailDebug("Missing group thread.")
                return nil
            }
            return groupThread.groupModel
        }) else {
            navigationController?.popViewController(animated: true)
            return
        }

        groupModel = newModel
        updateTableContents()
    }

    private func showRevokePendingInviteFromLocalUserConfirmation(invitedAddress: SignalServiceAddress) {

        let invitedName = contactsManager.displayName(for: invitedAddress)
        let format = NSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_INVITE_CONFIRMATION_TITLE_1_FORMAT",
                                       comment: "Format for title of 'revoke invite' confirmation alert. Embeds {{ the name of the invited group member. }}.")
        let alertTitle = String(format: format, invitedName)
        let actionSheet = ActionSheetController(title: alertTitle)
        actionSheet.addAction(ActionSheetAction(title: NSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_INVITE_1_BUTTON",
                                                                         comment: "Title of 'revoke invite' button."),
                                                style: .destructive) { _ in
                                                    self.revokePendingInvites(addresses: [invitedAddress])
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }

    private func showRevokePendingInviteFromOtherUserConfirmation(invitedAddresses: [SignalServiceAddress],
                                                                  inviterAddress: SignalServiceAddress) {

        let inviterName = contactsManager.displayName(for: inviterAddress)
        let format = NSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_INVITE_CONFIRMATION_TITLE_N_FORMAT",
                                       comment: "Format for title of 'revoke invite' confirmation alert. Embeds {{ %1$@ the number of users they have invited, %2$@ name of the inviting group member. }}.")
        let alertTitle = String(format: format, OWSFormat.formatInt(invitedAddresses.count), inviterName)
        let actionSheet = ActionSheetController(title: alertTitle)
        let actionTitle = (invitedAddresses.count > 1
            ? NSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_INVITE_N_BUTTON",
                                comment: "Title of 'revoke invites' button.")
            : NSLocalizedString("PENDING_GROUP_MEMBERS_REVOKE_INVITE_1_BUTTON",
                                comment: "Title of 'revoke invite' button."))
        actionSheet.addAction(ActionSheetAction(title: actionTitle,
                                                style: .destructive) { _ in
                                                    self.revokePendingInvites(addresses: invitedAddresses)
        })
        actionSheet.addAction(OWSActionSheets.cancelAction)
        presentActionSheet(actionSheet)
    }
}

// MARK: -

private extension PendingGroupMembersViewController {

    func revokePendingInvites(addresses: [SignalServiceAddress]) {
        GroupViewUtils.updateGroupWithActivityIndicator(fromViewController: self,
                                                        updatePromiseBlock: {
                                                            self.revokePendingInvitesPromise(addresses: addresses)
        },
                                                        completion: {
                                                            self.reloadGroupModelAndTableContents()
        })
    }

    func revokePendingInvitesPromise(addresses: [SignalServiceAddress]) -> Promise<Void> {
        guard let groupModelV2 = groupModel as? TSGroupModelV2 else {
            return Promise(error: OWSAssertionError("Invalid group model."))
        }
        let uuids = addresses.compactMap { $0.uuid }
        guard !uuids.isEmpty else {
            return Promise(error: OWSAssertionError("Invalid addresses."))
        }

        return firstly { () -> Promise<Void> in
            return GroupManager.messageProcessingPromise(for: groupModel,
                                                         description: self.logTag)
        }.then(on: .global()) { _ in
            GroupManager.removeFromGroupOrRevokeInviteV2(groupModel: groupModelV2, uuids: uuids)
        }.asVoid()
    }
}
