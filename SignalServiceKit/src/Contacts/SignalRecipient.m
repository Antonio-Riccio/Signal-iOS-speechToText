//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "SignalRecipient.h"
#import "OWSDevice.h"
#import "ProfileManagerProtocol.h"
#import "SSKEnvironment.h"
#import "SSKSessionStore.h"
#import "TSAccountManager.h"
#import "TSSocketManager.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

const NSUInteger SignalRecipientSchemaVersion = 1;

@interface SignalRecipient ()

@property (nonatomic) NSOrderedSet<NSNumber *> *devices;
@property (nonatomic) NSUInteger recipientSchemaVersion;

@end

#pragma mark -

@implementation SignalRecipient

#pragma mark - Dependencies

- (id<ProfileManagerProtocol>)profileManager
{
    return SSKEnvironment.shared.profileManager;
}

- (id<OWSUDManager>)udManager
{
    return SSKEnvironment.shared.udManager;
}

- (TSAccountManager *)tsAccountManager
{
    OWSAssertDebug(SSKEnvironment.shared.tsAccountManager);
    
    return SSKEnvironment.shared.tsAccountManager;
}

- (TSSocketManager *)socketManager
{
    OWSAssertDebug(SSKEnvironment.shared.socketManager);
    
    return SSKEnvironment.shared.socketManager;
}

- (id<StorageServiceManagerProtocol>)storageServiceManager
{
    return SSKEnvironment.shared.storageServiceManager;
}

+ (id<StorageServiceManagerProtocol>)storageServiceManager
{
    return SSKEnvironment.shared.storageServiceManager;
}

+ (SSKSessionStore *)sessionStore
{
    return SSKEnvironment.shared.sessionStore;
}

+ (SignalRecipientReadCache *)signalRecipientReadCache
{
    return SSKEnvironment.shared.modelReadCaches.signalRecipientReadCache;
}

- (SignalRecipientReadCache *)signalRecipientReadCache
{
    return SSKEnvironment.shared.modelReadCaches.signalRecipientReadCache;
}

#pragma mark -

+ (instancetype)getOrBuildUnsavedRecipientForAddress:(SignalServiceAddress *)address
                                         transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(address.isValid);

    SignalRecipient *_Nullable recipient = [self registeredRecipientForAddress:address
                                                               mustHaveDevices:NO
                                                                   transaction:transaction];
    if (!recipient) {
        recipient = [[self alloc] initWithAddress:address];
    }
    return recipient;
}

- (instancetype)initWithUUIDString:(NSString *)uuidString
{
    self = [super init];

    if (!self) {
        return self;
    }

    _recipientUUID = uuidString;
    _recipientPhoneNumber = nil;
    _recipientSchemaVersion = SignalRecipientSchemaVersion;

    _devices = [NSOrderedSet orderedSetWithObject:@(OWSDevicePrimaryDeviceId)];

    return self;
}

- (instancetype)initWithAddress:(SignalServiceAddress *)address
{
    self = [super init];

    if (!self) {
        return self;
    }

    _recipientUUID = address.uuidString;
    _recipientPhoneNumber = address.phoneNumber;
    _recipientSchemaVersion = SignalRecipientSchemaVersion;

    _devices = [NSOrderedSet orderedSetWithObject:@(OWSDevicePrimaryDeviceId)];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (!self) {
        return self;
    }

    if (_devices == nil) {
        _devices = [NSOrderedSet new];
    }

    // Migrating from an everyone has a phone number world to a
    // world in which we have UUIDs
    if (_recipientSchemaVersion < 1) {
        // Copy uniqueId to recipientPhoneNumber
        _recipientPhoneNumber = [coder decodeObjectForKey:@"uniqueId"];

        OWSAssert(_recipientPhoneNumber != nil);
    }

    // Since we use device count to determine whether a user is registered or not,
    // ensure the local user always has at least *this* device.
    if (![_devices containsObject:@(OWSDevicePrimaryDeviceId)]) {
        if (self.address.isLocalAddress) {
            DDLogInfo(@"Adding primary device to self recipient.");
            [self addDevices:[NSSet setWithObject:@(OWSDevicePrimaryDeviceId)]];
        }
    }

    _recipientSchemaVersion = SignalRecipientSchemaVersion;

    return self;
}

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
                         devices:(NSOrderedSet<NSNumber *> *)devices
            recipientPhoneNumber:(nullable NSString *)recipientPhoneNumber
                   recipientUUID:(nullable NSString *)recipientUUID
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId];

    if (!self) {
        return self;
    }

    _devices = devices;
    _recipientPhoneNumber = recipientPhoneNumber;
    _recipientUUID = recipientUUID;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

+ (AnySignalRecipientFinder *)recipientFinder
{
    return [AnySignalRecipientFinder new];
}

+ (nullable instancetype)registeredRecipientForAddress:(SignalServiceAddress *)address
                                       mustHaveDevices:(BOOL)mustHaveDevices
                                           transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(address.isValid);
    SignalRecipient *_Nullable signalRecipient =
        [self.signalRecipientReadCache getSignalRecipientForAddress:address transaction:transaction];
    if (mustHaveDevices && signalRecipient.devices.count < 1) {
        return nil;
    }
    return signalRecipient;
}

#pragma mark -

- (void)addDevices:(NSSet<NSNumber *> *)devices
{
    OWSAssertDebug(devices.count > 0);

    NSMutableOrderedSet<NSNumber *> *updatedDevices = [self.devices mutableCopy];
    [updatedDevices unionSet:devices];
    self.devices = [updatedDevices copy];
}

- (void)removeDevices:(NSSet<NSNumber *> *)devices
{
    OWSAssertDebug(devices.count > 0);

    NSMutableOrderedSet<NSNumber *> *updatedDevices = [self.devices mutableCopy];
    [updatedDevices minusSet:devices];
    self.devices = [updatedDevices copy];
}

- (void)updateRegisteredRecipientWithDevicesToAdd:(nullable NSArray<NSNumber *> *)devicesToAdd
                                  devicesToRemove:(nullable NSArray<NSNumber *> *)devicesToRemove
                                      transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(devicesToAdd.count > 0 || devicesToRemove.count > 0);

    // Add before we remove, since removeDevicesFromRecipient:...
    // can markRecipientAsUnregistered:... if the recipient has
    // no devices left.
    if (devicesToAdd.count > 0) {
        [self addDevicesToRegisteredRecipient:[NSSet setWithArray:devicesToAdd] transaction:transaction];
    }
    if (devicesToRemove.count > 0) {
        [self removeDevicesFromRecipient:[NSSet setWithArray:devicesToRemove] transaction:transaction];
    }

    // Device changes
    dispatch_async(dispatch_get_main_queue(), ^{
        // Device changes can affect the UD access mode for a recipient,
        // so we need to fetch the profile for this user to update UD access mode.
        [self.profileManager fetchProfileForAddress:self.address];

        if (self.address.isLocalAddress) {
            [self.socketManager cycleSocket];
        }
    });
}

- (void)addDevicesToRegisteredRecipient:(NSSet<NSNumber *> *)devices transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(devices.count > 0);
    OWSLogDebug(@"adding devices: %@, to recipient: %@", devices, self);

    [self anyReloadWithTransaction:transaction];
    [self anyUpdateWithTransaction:transaction
                             block:^(SignalRecipient *signalRecipient) {
                                 [signalRecipient addDevices:devices];
                             }];
}

- (void)removeDevicesFromRecipient:(NSSet<NSNumber *> *)devices transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(devices.count > 0);

    OWSLogDebug(@"removing devices: %@, from registered recipient: %@", devices, self);
    [self anyReloadWithTransaction:transaction ignoreMissing:YES];
    [self anyUpdateWithTransaction:transaction
                             block:^(SignalRecipient *signalRecipient) {
                                 [signalRecipient removeDevices:devices];
                             }];
}

#pragma mark -

- (SignalServiceAddress *)address
{
    return [[SignalServiceAddress alloc] initWithUuidString:self.recipientUUID phoneNumber:self.recipientPhoneNumber];
}

#pragma mark -

- (NSComparisonResult)compare:(SignalRecipient *)other
{
    return [self.address compare:other.address];
}

- (void)anyWillInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyWillInsertWithTransaction:transaction];

    OWSLogVerbose(@"Inserted signal recipient: %@ (%lu)", self.address, (unsigned long)self.devices.count);
}

- (void)anyWillUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyWillUpdateWithTransaction:transaction];

    OWSLogVerbose(@"Updated signal recipient: %@ (%lu)", self.address, (unsigned long)self.devices.count);
}

+ (BOOL)isRegisteredRecipient:(SignalServiceAddress *)address transaction:(SDSAnyReadTransaction *)transaction
{
    OWSAssertDebug(transaction);
    OWSAssertDebug(address.isValid);
    return nil != [self registeredRecipientForAddress:address mustHaveDevices:YES transaction:transaction];
}

+ (SignalRecipient *)markRecipientAsRegisteredAndGet:(SignalServiceAddress *)address
                                          trustLevel:(SignalRecipientTrustLevel)trustLevel
                                         transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(transaction);

    SignalRecipient *_Nullable phoneNumberInstance = nil;
    SignalRecipient *_Nullable uuidInstance = nil;
    if (address.phoneNumber != nil) {
        phoneNumberInstance = [self.recipientFinder signalRecipientForPhoneNumber:address.phoneNumber
                                                                      transaction:transaction];
    }
    if (address.uuid != nil) {
        uuidInstance = [self.recipientFinder signalRecipientForUUID:address.uuid transaction:transaction];
    }

    switch (trustLevel) {
        // Low trust updates should never update the database, unless
        // there is no matching record for the UUID, in which case we
        // can create a new UUID only record (we don't want to associate
        // it with the phone number)
        case SignalRecipientTrustLevelLow:
            if (uuidInstance) {
                return uuidInstance;
            } else if (address.uuidString) {
                OWSLogDebug(@"creating new low trust recipient with UUID: %@", address.uuidString);

                SignalRecipient *newInstance = [[self alloc] initWithUUIDString:address.uuidString];
                [newInstance anyInsertWithTransaction:transaction];

                // Record with the new contact in the social graph
                [self.storageServiceManager recordPendingUpdatesWithUpdatedAccountIds:@[ newInstance.accountId ]];

                return newInstance;
            } else if (phoneNumberInstance) {
                return phoneNumberInstance;
            } else {
                OWSFailDebug(@"Unexpectedly received new low trust address without UUID, creating unsaved placeholder "
                             @"recipient");
                return [self getOrBuildUnsavedRecipientForAddress:address transaction:transaction];
            }

        // High trust updates will fully update the database to reflect
        // the new mapping in a given address, if any changes are present.
        //
        // In general, the rules we follow when applying changes are:
        // * UUIDs are immutable and representative of an account. If the UUID
        //   has changed we must treat it as an entirely new contact.
        // * Phone numbers are transient and can move freely between UUIDs. When
        //   they do, we must backfill the database to reflect the change.
        case SignalRecipientTrustLevelHigh: {
            BOOL shouldUpdate = NO;
            SignalRecipient *_Nullable existingInstance = nil;

            if (uuidInstance && phoneNumberInstance) {
                // These are the same and both fully complete, we have no extra work to do.
                if ([NSObject isNullableObject:phoneNumberInstance.recipientPhoneNumber
                                       equalTo:uuidInstance.recipientPhoneNumber]
                    && [NSObject isNullableObject:phoneNumberInstance.recipientUUID
                                          equalTo:uuidInstance.recipientUUID]) {
                    existingInstance = phoneNumberInstance;

                // These are the same, but not fully complete. We need to merge them.
                } else if (phoneNumberInstance.recipientUUID == nil ||
                    [NSObject isNullableObject:phoneNumberInstance.recipientUUID equalTo:uuidInstance.recipientUUID]) {
                    existingInstance = [self mergeUUIDInstance:uuidInstance
                                        andPhoneNumberInstance:phoneNumberInstance
                                                   transaction:transaction];
                    shouldUpdate = YES;

                // The UUID differs between the two records, we need to migrate the phone
                // number to the UUID instance.
                } else {
                    OWSLogWarn(
                        @"Learned phoneNumber (%@) now belongs to uuid (%@).", address.phoneNumber, address.uuid);

                    // Ordering is critical here. We must remove the phone number
                    // from the old recipient *before* we assign the phone number
                    // to the new recipient, in case there are any legacy phone
                    // number only records in the database.

                    shouldUpdate = YES;

                    OWSAssertDebug(phoneNumberInstance.recipientUUID != nil);
                    [phoneNumberInstance changePhoneNumber:nil transaction:transaction.unwrapGrdbWrite];
                    [uuidInstance changePhoneNumber:address.phoneNumber transaction:transaction.unwrapGrdbWrite];

                    existingInstance = uuidInstance;
                }
            } else if (phoneNumberInstance) {
                if (address.uuidString && phoneNumberInstance.recipientUUID != nil) {
                    OWSLogWarn(
                        @"Learned phoneNumber (%@) now belongs to uuid (%@).", address.phoneNumber, address.uuid);

                    // The UUID associated with this phone number has changed, we must
                    // clear the phone number from this instance and create a new instance.
                    [phoneNumberInstance changePhoneNumber:nil transaction:transaction.unwrapGrdbWrite];
                } else {
                    if (address.uuidString) {
                        OWSLogWarn(@"Learned uuid (%@) is associated with phoneNumber (%@).",
                            address.uuidString,
                            address.phoneNumber);

                        shouldUpdate = YES;
                        phoneNumberInstance.recipientUUID = address.uuidString;
                    }

                    existingInstance = phoneNumberInstance;
                }
            } else if (uuidInstance) {
                if (address.phoneNumber) {
                    if (uuidInstance.recipientPhoneNumber == nil) {
                        OWSLogWarn(@"Learned uuid (%@) is associated with phoneNumber (%@).",
                            address.uuidString,
                            address.phoneNumber);
                    } else {
                        OWSLogWarn(@"Learned uuid (%@) changed from old phoneNumber (%@) to new phoneNumber (%@)",
                            address.uuidString,
                            existingInstance.recipientPhoneNumber,
                            address.phoneNumber);
                    }

                    shouldUpdate = YES;
                    [uuidInstance changePhoneNumber:address.phoneNumber transaction:transaction.unwrapGrdbWrite];
                }

                existingInstance = uuidInstance;
            }

            if (existingInstance == nil) {
                OWSLogDebug(@"creating new high trust recipient with address: %@", address);

                SignalRecipient *newInstance = [[self alloc] initWithAddress:address];
                [newInstance anyInsertWithTransaction:transaction];

                // Record with the new contact in the social graph
                [self.storageServiceManager recordPendingUpdatesWithUpdatedAccountIds:@[ newInstance.accountId ]];

                return newInstance;
            }

            if (existingInstance.devices.count == 0) {
                shouldUpdate = YES;

                // We know they're registered, so make sure they have at least one device.
                // We assume it's the default device. If we're wrong, the service will correct us when we
                // try to send a message to them
                existingInstance.devices = [NSOrderedSet orderedSetWithObject:@(OWSDevicePrimaryDeviceId)];
            }

            // Record the updated contact in the social graph
            if (shouldUpdate) {
                [existingInstance anyOverwritingUpdateWithTransaction:transaction];
                [self.storageServiceManager recordPendingUpdatesWithUpdatedAccountIds:@[ existingInstance.accountId ]];
            }

            return existingInstance;
        }
    }
}

+ (SignalRecipient *)mergeUUIDInstance:(SignalRecipient *)uuidInstance
                andPhoneNumberInstance:(SignalRecipient *)phoneNumberInstance
                           transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(uuidInstance.recipientPhoneNumber == nil ||
        [NSObject isNullableObject:uuidInstance.recipientPhoneNumber equalTo:phoneNumberInstance.recipientPhoneNumber]);
    OWSAssertDebug(phoneNumberInstance.recipientUUID == nil ||
        [NSObject isNullableObject:phoneNumberInstance.recipientUUID equalTo:uuidInstance.recipientUUID]);

    // We have separate recipients in the db for the uuid and phone number.
    // There isn't an ideal way to do this, but we need to converge on one
    // recipient and discard the other.
    //
    // TODO: Should we clean up any state related to the discarded recipient?

    SignalRecipient *_Nullable winningInstance = nil;

    // We try to preserve the recipient that has a session.
    NSNumber *_Nullable sessionIndexForUuid =
        [self.sessionStore maxSessionSenderChainKeyIndexForAccountId:uuidInstance.accountId transaction:transaction];
    NSNumber *_Nullable sessionIndexForPhoneNumber =
        [self.sessionStore maxSessionSenderChainKeyIndexForAccountId:phoneNumberInstance.accountId
                                                         transaction:transaction];

    if (SSKDebugFlags.verboseSignalRecipientLogging) {
        OWSLogInfo(@"phoneNumberInstance: %@", phoneNumberInstance);
        OWSLogInfo(@"uuidInstance: %@", uuidInstance);
        OWSLogInfo(@"sessionIndexForUuid: %@", sessionIndexForUuid);
        OWSLogInfo(@"sessionIndexForPhoneNumber: %@", sessionIndexForPhoneNumber);
    }

    // We want to retain the phone number recipient if it
    // has a session and the uuid recipient doesn't or if
    // both have a session but the phone number recipient
    // has seen more use.
    //
    // All things being equal, we default to retaining the
    // UUID recipient.
    BOOL shouldUseUuid = (sessionIndexForPhoneNumber.intValue <= sessionIndexForUuid.intValue);
    if (shouldUseUuid) {
        OWSLogWarn(@"Discarding phone number recipient in favor of uuid recipient.");
        winningInstance = uuidInstance;
        [phoneNumberInstance anyRemoveWithTransaction:transaction];
    } else {
        OWSLogWarn(@"Discarding uuid recipient in favor of phone number recipient.");
        winningInstance = phoneNumberInstance;
        [uuidInstance anyRemoveWithTransaction:transaction];
    }

    // Make sure the winning instance is fully qualified.
    winningInstance.recipientPhoneNumber = phoneNumberInstance.recipientPhoneNumber;
    winningInstance.recipientUUID = uuidInstance.recipientUUID;

    [OWSUserProfile mergeUserProfilesIfNecessaryForAddress:winningInstance.address transaction:transaction];

    return winningInstance;
}

+ (void)markRecipientAsRegistered:(SignalServiceAddress *)address
                         deviceId:(UInt32)deviceId
                       trustLevel:(SignalRecipientTrustLevel)trustLevel
                      transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(deviceId > 0);
    OWSAssertDebug(transaction);

    SignalRecipient *recipient = [self markRecipientAsRegisteredAndGet:address
                                                            trustLevel:trustLevel
                                                           transaction:transaction];
    if (![recipient.devices containsObject:@(deviceId)]) {
        OWSLogDebug(@"Adding device %u to existing recipient.", (unsigned int)deviceId);

        [recipient anyReloadWithTransaction:transaction];
        [recipient anyUpdateWithTransaction:transaction
                                      block:^(SignalRecipient *signalRecipient) {
                                          [signalRecipient addDevices:[NSSet setWithObject:@(deviceId)]];
                                      }];
    }
}

+ (void)markRecipientAsUnregistered:(SignalServiceAddress *)address transaction:(SDSAnyWriteTransaction *)transaction
{
    OWSAssertDebug(address.isValid);
    OWSAssertDebug(transaction);

    SignalRecipient *recipient = [self getOrBuildUnsavedRecipientForAddress:address transaction:transaction];
    if (recipient.devices.count > 0) {
        OWSLogDebug(@"Marking recipient as not registered: %@", address);
        if ([SignalRecipient anyFetchWithUniqueId:recipient.uniqueId transaction:transaction] == nil) {
            [recipient removeDevices:recipient.devices.set];
            [recipient anyInsertWithTransaction:transaction];
        } else {
            [recipient anyUpdateWithTransaction:transaction
                                          block:^(SignalRecipient *signalRecipient) {
                                              signalRecipient.devices = [NSOrderedSet new];
                                          }];
        }

        // Remove the contact from our social graph
        [self.storageServiceManager recordPendingDeletionsWithDeletedAccountIds:@[ recipient.accountId ]];
    }
}

- (void)anyDidInsertWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidInsertWithTransaction:transaction];

    [self.signalRecipientReadCache didInsertOrUpdateSignalRecipient:self transaction:transaction];
}

- (void)anyDidUpdateWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidUpdateWithTransaction:transaction];

    [self.signalRecipientReadCache didInsertOrUpdateSignalRecipient:self transaction:transaction];
}

- (void)anyDidRemoveWithTransaction:(SDSAnyWriteTransaction *)transaction
{
    [super anyDidRemoveWithTransaction:transaction];

    [self.signalRecipientReadCache didRemoveSignalRecipient:self transaction:transaction];
    [self.storageServiceManager recordPendingDeletionsWithDeletedAccountIds:@[ self.accountId ]];
}

+ (BOOL)shouldBeIndexedForFTS
{
    return YES;
}

@end

NS_ASSUME_NONNULL_END
