(function() {
  var Barcode, Business, BusinessRequest, BusinessTransaction, CardRequest, Client, ClientInvitation, Comment, Consumer, DBTransaction, Discussion, DocumentArray, Donor, Email, EmailSubmission, Entity, Event, EventDateRange, EventRequest, Goody, Location, Media, ObjectId, Organization, PasswordResetRequest, Poll, ProfileEntry, RedemptionLog, Reference, Referral, RegisterData, Response, Schema, Sequence, Statistic, Stream, Tag, Transaction, UnclaimedBarcodeStatistic, Url, choices, countries, defaults, donor, entity, exports, globals, location, loggers, media, mongoose, organization, reference, registerData, transaction, transactions, utils;

  exports = module.exports;

  globals = require('globals');

  loggers = require("./loggers");

  utils = globals.utils;

  defaults = globals.defaults;

  choices = globals.choices;

  countries = globals.countries;

  mongoose = globals.mongoose;

  Schema = mongoose.Schema;

  ObjectId = mongoose.SchemaTypes.ObjectId;

  DocumentArray = mongoose.SchemaTypes.DocumentArray;

  Url = /(ftp|http|https):\/\/(\w+:{0,1}\w*@)?(\S+)(:[0-9]+)?(\/|\/([\w#!:.?+=&%@!\-\/]))?/;

  Email = /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$/;

  reference = {
    type: {
      type: String,
      required: true
    },
    id: {
      type: ObjectId,
      required: true
    }
  };

  entity = {
    type: {
      type: String,
      required: true,
      "enum": choices.entities._enum
    },
    id: {
      type: ObjectId,
      required: true
    },
    name: {
      type: String
    },
    screenName: {
      type: String
    },
    by: {
      type: {
        type: String,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId
      },
      name: {
        type: String
      }
    }
  };

  donor = {
    entity: entity,
    funds: {
      remaining: {
        type: Number,
        required: true,
        "default": 0.0
      },
      allocated: {
        type: Number,
        required: true,
        "default": 0.0
      }
    }
  };

  organization = {
    type: {
      type: String,
      required: true,
      "enum": choices.organizations._enum
    },
    id: {
      type: ObjectId,
      required: true
    },
    name: {
      type: String
    }
  };

  location = {
    name: {
      type: String
    },
    street1: {
      type: String,
      required: true
    },
    street2: {
      type: String
    },
    city: {
      type: String,
      required: true
    },
    state: {
      type: String,
      required: true
    },
    zip: {
      type: Number,
      required: true
    },
    country: {
      type: String,
      "enum": countries.codes,
      required: true,
      "default": "us"
    },
    phone: {
      type: String
    },
    fax: {
      type: String
    },
    lat: {
      type: Number
    },
    lng: {
      type: Number
    },
    tapins: {
      type: Boolean
    }
  };

  transaction = {
    id: {
      type: ObjectId,
      required: true
    },
    state: {
      type: String,
      required: true,
      "enum": choices.transactions.states._enum
    },
    action: {
      type: String,
      required: true,
      "enum": choices.transactions.actions._enum
    },
    error: {
      message: {
        type: String
      }
    },
    dates: {
      created: {
        type: Date,
        required: true,
        "default": Date.now
      },
      completed: {
        type: Date
      },
      lastModified: {
        type: Date,
        required: true,
        "default": Date.now
      }
    },
    data: {},
    direction: {
      type: String,
      required: true,
      "enum": choices.transactions.directions._enum
    },
    entity: {
      type: {
        type: String,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId
      },
      name: {
        type: String
      },
      screenName: {
        type: String
      }
    },
    attempts: {
      type: Number,
      "default": 0
    },
    pollerId: {
      type: ObjectId
    }
  };

  transactions = {
    ids: [ObjectId],
    failed: [ObjectId],
    log: [Transaction],
    temp: [Transaction],
    locked: {
      type: Boolean
    },
    state: {
      type: String,
      "enum": choices.transactions.states._enum
    }
  };

  media = {
    url: {
      type: String,
      validate: Url
    },
    thumb: {
      type: String,
      validate: Url
    },
    guid: {
      type: String
    },
    mediaId: {
      type: ObjectId
    },
    rotateDegrees: {
      type: Number
    }
  };

  registerData = {
    registerId: {
      type: ObjectId,
      required: true
    },
    setupId: {
      type: Number,
      required: true
    }
  };

  ProfileEntry = new Schema({
    name: {
      type: String
    },
    type: {
      type: String
    }
  });

  Reference = new Schema(reference);

  Entity = new Schema(entity);

  Location = new Schema(location);

  Donor = new Schema(donor);

  Transaction = new Schema(transaction);

  RegisterData = new Schema(registerData);

  DBTransaction = new Schema({
    document: {
      type: {
        type: String,
        required: true
      },
      id: {
        type: ObjectId,
        required: true
      }
    },
    timestamp: {
      type: Date,
      "default": Date.now
    },
    transaction: transaction
  });

  DBTransaction.index({
    "document.type": 1,
    "document.id": 1,
    "transaction.id": 1
  }, {
    unique: true
  });

  DBTransaction.index({
    "transaction.id": 1,
    "transaction.state": 1,
    "transaction.action": 1
  });

  DBTransaction.index({
    "transaction.state": 1
  });

  DBTransaction.index({
    "transaction.action": 1
  });

  DBTransaction.index({
    "entity.type": 1,
    "entity.id": 1
  });

  DBTransaction.index({
    "by.type": 1,
    "by.id": 1
  });

  Sequence = new Schema({
    urlShortner: {
      type: Number,
      "default": 0
    },
    barcodeId: {
      type: Number,
      "default": 0
    }
  });

  Barcode = new Schema({
    barcodeId: {
      type: String,
      required: true
    }
  });

  Barcode.index({
    "barcodeId": 1
  }, {
    unique: true
  });

  PasswordResetRequest = new Schema({
    date: {
      type: Date,
      "default": Date.now
    },
    key: {
      type: String,
      required: true,
      unique: true
    },
    entity: {
      type: {
        type: String,
        required: true,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId,
        required: true
      },
      name: {
        type: String
      }
    },
    consumed: {
      type: Boolean,
      "default": false
    }
  });

  Consumer = new Schema({
    email: {
      type: String,
      set: utils.toLower,
      validate: Email,
      unique: true
    },
    password: {
      type: String,
      min: 5,
      required: true
    },
    firstName: {
      type: String
    },
    lastName: {
      type: String
    },
    privateId: {
      type: ObjectId
    },
    screenName: {
      type: String,
      min: 5
    },
    aliasId: {
      type: ObjectId
    },
    setScreenName: {
      type: Boolean,
      "default": false
    },
    created: {
      type: Date,
      "default": Date.now
    },
    logins: [],
    loginCount: {
      type: Number,
      "default": 1
    },
    honorScore: {
      type: Number,
      "default": 0
    },
    charities: {},
    media: media,
    secureMedia: media,
    tapinsToFacebook: {
      type: Boolean,
      "default": false
    },
    changeEmail: {},
    charity: {
      type: {
        type: String,
        "enum": [choices.organizations.CHARITY]
      },
      id: {
        type: ObjectId
      },
      name: {
        type: String
      }
    },
    facebook: {
      access_token: {
        type: String
      },
      id: {
        type: String
      }
    },
    profile: {
      birthday: {
        type: Date
      },
      gender: {},
      education: [ProfileEntry],
      work: [ProfileEntry],
      location: {},
      hometown: {},
      interests: [ProfileEntry],
      aboutme: {},
      timezone: {},
      affiliations: [ObjectId]
    },
    permissions: {
      email: {
        type: Boolean,
        "default": false
      },
      media: {
        type: Boolean,
        "default": true
      },
      birthday: {
        type: Boolean,
        "default": false
      },
      gender: {
        type: Boolean,
        "default": false
      },
      education: {
        type: Boolean,
        "default": false
      },
      work: {
        type: Boolean,
        "default": false
      },
      location: {
        type: Boolean,
        "default": false
      },
      hometown: {
        type: Boolean,
        "default": false
      },
      interests: {
        type: Boolean,
        "default": false
      },
      fbinterests: {
        type: Boolean,
        "default": false
      },
      aboutme: {
        type: Boolean,
        "default": false
      },
      timezone: {
        type: Boolean,
        "default": false
      },
      affiliations: {
        type: Boolean,
        "default": false
      },
      hiddenFacebookItems: {
        work: [
          {
            type: String
          }
        ],
        education: [
          {
            type: String
          }
        ]
      }
    },
    funds: {
      allocated: {
        type: Number,
        "default": 0.0,
        required: true
      },
      remaining: {
        type: Number,
        "default": 0.0,
        required: true
      },
      donated: {
        type: Number,
        "default": 0.0,
        required: true
      }
    },
    donations: {
      log: {},
      charities: [ObjectId]
    },
    referralCodes: {
      tapIn: {
        type: String
      },
      user: {
        type: String
      }
    },
    barcodeId: {
      type: String
    },
    gbAdmin: {
      type: Boolean,
      "default": false
    },
    updateVerification: {
      key: {
        type: String
      },
      expiration: {
        type: Date
      },
      data: {}
    },
    signUpVerification: {
      key: {
        type: String
      },
      expiration: {
        type: Date
      }
    },
    transactions: transactions
  });

  Consumer.index({
    screenName: 1
  }, {
    unique: true,
    sparse: true
  });

  Consumer.index({
    barcodeId: 1
  }, {
    unique: true,
    sparse: true
  });

  Consumer.index({
    email: 1
  });

  Consumer.index({
    "facebook.id": 1,
    email: 1
  });

  Consumer.index({
    "signUpVerification.key": 1
  });

  Consumer.index({
    "updateVerification.key": 1
  });

  Consumer.index({
    "updateVerification.data.barcodeId": 1,
    "updateVerification.expiration": 1
  });

  Consumer.index({
    _id: 1,
    "transactions.ids": 1
  });

  Consumer.index({
    "transactions.ids": 1
  });

  Client = new Schema({
    firstName: {
      type: String,
      required: true
    },
    lastName: {
      type: String,
      required: true
    },
    email: {
      type: String,
      index: true,
      unique: true,
      set: utils.toLower,
      validate: Email
    },
    password: {
      type: String,
      validate: /.{5,}/,
      required: true
    },
    changeEmail: {},
    media: media,
    dates: {
      created: {
        type: Date,
        required: true,
        "default": Date.now
      }
    },
    funds: {
      allocated: {
        type: Number,
        required: true,
        "default": 0.0
      },
      remaining: {
        type: Number,
        required: true,
        "default": 0.0
      }
    },
    transactions: transactions
  });

  Business = new Schema({
    name: {
      type: String,
      required: true
    },
    publicName: {
      type: String,
      required: true
    },
    type: [
      {
        type: String,
        required: true
      }
    ],
    tags: [
      {
        type: String,
        required: true
      }
    ],
    url: {
      type: String,
      validate: Url
    },
    email: {
      type: String,
      validate: Email
    },
    isCharity: {
      type: Boolean,
      "default": false
    },
    legal: {
      street1: {
        type: String,
        required: true
      },
      street2: {
        type: String
      },
      city: {
        type: String,
        required: true
      },
      state: {
        type: String,
        required: true
      },
      zip: {
        type: Number,
        required: true
      },
      country: {
        type: String,
        "enum": countries.codes,
        required: true,
        "default": "us"
      },
      phone: {
        type: String,
        required: true
      },
      fax: {
        type: String
      }
    },
    registers: {},
    locRegister: {},
    registerData: [RegisterData],
    locations: [Location],
    media: media,
    clients: [ObjectId],
    clientGroups: {},
    groups: {
      owners: [ObjectId],
      managers: [ObjectId]
    },
    dates: {
      created: {
        type: Date,
        required: true,
        "default": Date.now
      }
    },
    funds: {
      allocated: {
        type: Number,
        required: true,
        "default": 0.0
      },
      remaining: {
        type: Number,
        required: true,
        "default": 0.0
      },
      donationsRecieved: {
        type: Number
      }
    },
    gbEquipped: {
      type: Boolean,
      "default": false
    },
    deleted: {
      type: Boolean,
      "default": false
    },
    pin: {
      type: String,
      validate: /[0-9]/
    },
    cardCode: {
      type: String
    },
    transactions: transactions,
    permissions: {}
  });

  Business.index({
    name: 1
  });

  Business.index({
    publicName: 1
  });

  Business.index({
    isCharity: 1
  });

  Business.index({
    deleted: 1
  });

  Organization = new Schema({
    type: {
      type: String,
      required: true
    },
    subType: {
      type: String,
      required: true
    },
    name: {
      type: String,
      required: true
    }
  });

  Organization.index({
    type: 1,
    name: 1
  }, {
    unique: true
  });

  Organization.index({
    type: 1,
    subType: 1,
    name: 1
  });

  Poll = new Schema({
    entity: {
      type: {
        type: String,
        required: true,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId,
        required: true
      },
      name: {
        type: String
      }
    },
    createdBy: {
      type: {
        type: String,
        required: true,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId,
        required: true
      }
    },
    lastModifiedBy: {
      type: {
        type: String,
        required: true,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId,
        required: true
      }
    },
    name: {
      type: String,
      required: true
    },
    type: {
      type: String,
      required: true,
      "enum": choices.polls.type._enum
    },
    question: {
      type: String,
      required: true
    },
    choices: [
      {
        type: String,
        required: true
      }
    ],
    numChoices: {
      type: Number,
      min: 2,
      required: true
    },
    showStats: {
      type: Boolean,
      required: true
    },
    displayName: {
      type: Boolean,
      required: true
    },
    responses: {
      remaining: {
        type: Number,
        required: true
      },
      max: {
        type: Number,
        min: 1,
        required: true
      },
      consumers: [
        {
          type: ObjectId,
          required: true,
          "default": new Array()
        }
      ],
      log: {},
      dates: [],
      choiceCounts: [
        {
          type: Number,
          required: true,
          "default": new Array()
        }
      ],
      flagConsumers: [
        {
          type: ObjectId,
          required: true,
          "default": new Array()
        }
      ],
      flagCount: {
        type: Number,
        required: true,
        "default": 0
      },
      skipConsumers: [
        {
          type: ObjectId,
          required: true,
          "default": new Array()
        }
      ],
      skipCount: {
        type: Number,
        required: true,
        "default": 0
      }
    },
    mediaQuestion: media,
    mediaResults: media,
    dates: {
      created: {
        type: Date,
        required: true,
        "default": Date.now
      },
      start: {
        type: Date,
        required: true
      },
      end: {
        type: Date
      }
    },
    funds: {
      perResponse: {
        type: Number,
        required: true
      },
      allocated: {
        type: Number,
        required: true,
        "default": 0.0
      },
      remaining: {
        type: Number,
        required: true,
        "default": 0.0
      }
    },
    deleted: {
      type: Boolean,
      "default": false
    },
    transactions: transactions
  });

  Discussion = new Schema({
    entity: {
      type: {
        type: String,
        required: true,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId,
        required: true
      },
      name: {
        type: String
      }
    },
    createdBy: {
      type: {
        type: String,
        required: true,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId,
        required: true
      }
    },
    lastModifiedBy: {
      type: {
        type: String,
        required: true,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId,
        required: true
      }
    },
    name: {
      type: String,
      required: true
    },
    question: {
      type: String,
      required: true
    },
    details: {
      type: String
    },
    tags: [String],
    displayName: {
      type: Boolean,
      required: true
    },
    displayMedia: {
      type: Boolean,
      required: true
    },
    media: media,
    thanker: [Entity],
    donors: [Entity],
    donationAmounts: {},
    dates: {
      created: {
        type: Date,
        required: true,
        "default": Date.now
      },
      start: {
        type: Date,
        required: true,
        "default": Date.now
      },
      end: {
        type: Date
      }
    },
    funds: {
      allocated: {
        type: Number,
        required: true,
        "default": 0.0
      },
      remaining: {
        type: Number,
        required: true,
        "default": 0.0
      },
      donations: {
        type: Number,
        required: true,
        "default": 0.0
      },
      thanks: {
        type: Number,
        required: true,
        "default": 0.0
      }
    },
    donationCount: {
      type: Number,
      required: true,
      "default": 0
    },
    thankCount: {
      type: Number,
      required: true,
      "default": 0
    },
    votes: {
      count: {
        type: Number,
        "default": 0
      },
      score: {
        type: Number,
        "default": 0
      },
      up: {
        type: Number,
        "default": 0
      },
      down: {
        type: Number,
        "default": 0
      }
    },
    flagged: {
      by: [Entity],
      count: {
        type: Number,
        "default": 0
      }
    },
    responseCount: {
      type: Number,
      required: true,
      "default": 0
    },
    responses: [Response],
    responseEntities: {},
    deleted: {
      type: Boolean,
      "default": false
    },
    transactions: transactions
  });

  Response = new Schema({
    entity: entity,
    content: {
      type: String
    },
    dates: {
      created: {
        type: Date,
        required: true,
        "default": Date.now
      },
      lastModified: {
        type: Date,
        required: true,
        "default": Date.now
      }
    },
    comments: [Comment],
    commentCount: {
      type: Number,
      required: true,
      "default": 0
    },
    votes: {
      count: {
        type: Number,
        "default": 0
      },
      score: {
        type: Number,
        "default": 0
      },
      up: {
        by: [Entity],
        ids: {},
        count: {
          type: Number,
          "default": 0
        }
      },
      down: {
        by: [Entity],
        ids: {},
        count: {
          type: Number,
          "default": 0
        }
      }
    },
    flagged: {
      by: [Entity],
      count: {
        type: Number,
        "default": 0
      }
    },
    earned: {
      type: Number,
      "default": 0.0
    },
    thanks: {
      count: {
        type: Number,
        "default": 0
      },
      amount: {
        type: Number,
        "default": 0.0
      },
      by: [
        {
          entity: entity,
          amount: {
            type: Number
          }
        }
      ]
    },
    donations: {
      count: {
        type: Number,
        "default": 0
      },
      amount: {
        type: Number,
        "default": 0.0
      },
      by: [
        {
          entity: entity,
          amount: {
            type: Number
          }
        }
      ]
    }
  });

  Comment = new Schema({
    entity: entity,
    content: {
      type: String
    },
    dates: {
      created: {
        type: Date,
        required: true,
        "default": Date.now
      },
      lastModified: {
        type: Date,
        required: true,
        "default": Date.now
      }
    },
    flagged: {
      by: [Entity],
      count: {
        type: Number,
        "default": 0
      }
    }
  });

  Media = new Schema({
    entity: {
      type: {
        type: String,
        required: true,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId,
        required: true
      },
      name: {
        type: String
      }
    },
    type: {
      type: String,
      required: true,
      "enum": choices.media.type._enum
    },
    name: {
      type: String,
      required: true
    },
    duration: {
      type: Number
    },
    thumbs: [],
    sizes: {},
    tags: [],
    dates: {
      created: {
        type: Date,
        required: true,
        "default": Date.now
      }
    },
    transactions: transactions,
    deleted: {
      type: Boolean,
      "default": false
    }
  });

  Media.index({
    'entity.type': 1,
    'entity.id': 1,
    type: 1
  });

  Media.index({
    'entity.type': 1,
    'entity.id': 1,
    tags: 1
  });

  Media.index({
    'entity.type': 1,
    'entity.id': 1,
    name: 1
  });

  Media.index({
    'entity.type': 1,
    'entity.id': 1,
    'dates.created': 1
  });

  Media.index({
    url: 1
  });

  Media.index({
    "guid": 1
  });

  ClientInvitation = new Schema({
    businessId: {
      type: ObjectId,
      required: true
    },
    groupName: {
      type: String,
      required: true
    },
    email: {
      type: String,
      required: true,
      validate: Email
    },
    key: {
      type: String,
      required: true
    },
    status: {
      type: String,
      required: true,
      "enum": choices.invitations.state._enum,
      "default": choices.invitations.state.PENDING
    },
    dates: {
      created: {
        type: Date,
        "default": Date.now
      },
      expires: {
        type: Date
      }
    },
    transactions: transactions
  });

  ClientInvitation.index({
    businessId: 1,
    groupName: 1,
    email: 1
  }, {
    unique: true
  });

  Stream = new Schema({
    who: entity,
    by: {
      type: {
        type: String,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId
      },
      name: {
        type: String
      }
    },
    entitiesInvolved: [Entity],
    what: reference,
    when: {
      type: Date,
      required: true,
      "default": Date.now
    },
    where: {
      org: {
        type: {
          type: String,
          "enum": choices.entities._enum
        },
        id: {
          type: ObjectId
        },
        name: {
          type: String
        }
      },
      locationId: {
        type: ObjectId
      },
      locationName: {
        type: String
      }
    },
    events: [
      {
        type: String,
        required: true,
        "enum": choices.eventTypes._enum
      }
    ],
    feeds: {
      global: {
        type: Boolean,
        required: true,
        "default": false
      }
    },
    dates: {
      created: {
        type: Date,
        "default": Date.now
      },
      lastModified: {
        type: Date
      }
    },
    data: {},
    feedSpecificData: {
      involved: {}
    },
    entitySpecificData: {},
    deleted: {
      type: Boolean,
      "default": false
    },
    transactions: transactions
  });

  Stream.index({
    "feeds.global": 1,
    "dates.lastModified": -1
  });

  Stream.index({
    "feeds.global": 1,
    "who.type": 1,
    "who.id": 1,
    events: 1
  });

  Stream.index({
    "who.type": 1,
    "who.id": 1,
    events: 1
  });

  Stream.index({
    "who.type": 1,
    "who.id": 1,
    "by.type": 1,
    "by.id": 1,
    events: 1
  });

  Stream.index({
    "what.type": 1,
    "what.id": 1
  });

  Stream.index({
    when: 1
  });

  Stream.index({
    events: 1
  });

  Stream.index({
    "entitiesInvolved.type": 1,
    "entitiesInvolved.id": 1,
    "who.type": 1,
    "who.id": 1
  });

  Stream.index({
    "entitiesInvolved.type": 1,
    "entitiesInvolved.id": 1,
    "who.type": 1,
    "who.screenName": 1
  });

  Stream.index({
    "where.org.type": 1,
    "where.org.id": 1
  });

  Tag = new Schema({
    name: {
      type: String,
      required: true
    },
    type: {
      type: String,
      required: true,
      "enum": choices.tags.types._enum
    },
    count: {
      type: Number
    },
    transactions: transactions
  });

  Tag.index({
    type: 1,
    name: 1
  }, {
    unique: true
  });

  EventDateRange = new Schema({
    start: {
      type: Date,
      required: true
    },
    end: {
      type: Date,
      required: true
    }
  });

  Event = new Schema({
    entity: {
      type: {
        type: String,
        required: true,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId,
        required: true
      },
      name: {
        type: String
      }
    },
    locationId: {
      type: ObjectId
    },
    location: location,
    dates: {
      requested: {
        type: Date,
        required: true
      },
      responded: {
        type: Date,
        required: true
      },
      actual: {
        type: Date,
        required: true
      }
    },
    hours: [EventDateRange],
    pledge: {
      type: Number,
      min: 0,
      max: 100,
      required: true
    },
    externalUrl: {
      type: String,
      validate: Url
    },
    rsvp: [ObjectId],
    rsvpUsers: {},
    details: {
      type: String
    },
    transactions: transactions,
    media: media
  });

  EventRequest = new Schema({
    userEntity: {
      type: {
        type: String,
        required: true,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId,
        required: true
      },
      name: {
        type: String
      }
    },
    organizationEntity: {
      type: {
        type: String,
        required: true,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId,
        required: true
      },
      name: {
        type: String
      }
    },
    date: {
      requested: {
        type: Date,
        "default": Date.now
      },
      responded: {
        type: Date
      }
    },
    transactions: transactions
  });

  BusinessTransaction = new Schema({
    userEntity: {
      type: {
        type: String,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId
      },
      name: {
        type: String
      },
      screenName: {
        type: String
      }
    },
    organizationEntity: organization,
    charity: organization,
    locationId: {
      type: ObjectId,
      required: true
    },
    registerId: {
      type: String,
      required: true
    },
    barcodeId: {
      type: String
    },
    transactionId: {
      type: String
    },
    date: {
      type: Date,
      required: true
    },
    time: {
      type: Date,
      required: true
    },
    amount: {
      type: Number,
      required: false
    },
    receipt: {
      type: Buffer,
      required: false
    },
    hasReceipt: {
      type: Boolean,
      required: true,
      "default": false
    },
    karmaPoints: {
      type: String,
      required: true
    },
    donationType: {
      type: String,
      required: true,
      "enum": choices.donationTypes._enum
    },
    donationValue: {
      type: Number,
      required: true
    },
    donationAmount: {
      type: Number,
      required: true,
      "default": 0
    },
    postToFacebook: {
      type: Boolean,
      required: true,
      "default": false
    },
    transactions: transactions
  });

  BusinessTransaction.index({
    barcodeId: 1,
    "organizationEntity.id": 1,
    "date": -1
  });

  BusinessTransaction.index({
    "transactions.ids": 1
  });

  BusinessRequest = new Schema({
    userEntity: {
      type: {
        type: String,
        required: false,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId,
        required: false
      },
      name: {
        type: String
      }
    },
    loggedin: {
      type: Boolean,
      required: true,
      "default": true
    },
    businessName: {
      type: String,
      require: true
    },
    date: {
      requested: {
        type: Date,
        "default": Date.now
      },
      read: {
        type: Date
      }
    }
  });

  Referral = new Schema({
    type: {
      type: String,
      "enum": choices.referrals.types._enum,
      required: true
    },
    entity: {
      type: {
        type: String,
        required: true,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId,
        required: true
      }
    },
    by: {
      type: {
        type: String,
        required: true,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId,
        required: true
      }
    },
    incentives: {
      referrer: {
        type: Number,
        required: true,
        "default": 0.0
      },
      referred: {
        type: Number,
        required: true,
        "default": 0.0
      }
    },
    stickers: {
      range: {
        start: {
          type: Number
        },
        stop: {
          type: Number
        }
      },
      eventId: {
        type: ObjectId
      }
    },
    link: {
      code: {
        type: String
      },
      url: {
        type: String,
        validate: Url
      },
      type: {
        type: String,
        "enum": choices.referrals.links.types._enum
      },
      visits: {
        type: Number
      }
    },
    signups: {
      type: Number,
      required: true,
      "default": 0
    },
    referredUsers: [Entity]
  });

  Referral.index({
    type: 1,
    'entity.type': 1,
    'entity.id': 1,
    'link.url': 1
  });

  Referral.index({
    type: 1,
    'stickers.range.start': 1,
    'stickers.range.stop': 1
  });

  Referral.index({
    type: 1,
    'stickers.eventId': 1
  });

  Referral.index({
    type: 1,
    'entity.type': 1,
    'entity.id': 1,
    'stickers.eventId': 1
  });

  Referral.index({
    type: 1,
    'link.code': 1
  });

  Referral.index({
    type: 1,
    'link.url': 1
  });

  Goody = new Schema({
    org: organization,
    name: {
      type: String,
      required: true
    },
    description: {
      type: String
    },
    active: {
      type: Boolean,
      "default": false,
      required: true
    },
    karmaPointsRequired: {
      type: Number,
      required: true
    }
  });

  Goody.index({
    "org.type": 1,
    "org.id": 1,
    "karmaPointsRequired": 1
  });

  RedemptionLog = new Schema({
    consumer: entity,
    org: organization,
    locationId: {
      type: ObjectId,
      required: true
    },
    registerId: {
      type: ObjectId,
      required: true
    },
    goody: {
      id: {
        type: ObjectId,
        required: true
      },
      name: {
        type: String,
        required: true
      },
      karmaPointsRequired: {
        type: Number,
        required: true
      }
    },
    dates: {
      created: {
        type: Date,
        "default": Date.now,
        required: true
      },
      redeemed: {
        type: Date,
        "default": Date.now,
        required: true
      }
    },
    transactions: transactions
  });

  Statistic = new Schema({
    org: organization,
    consumerId: {
      type: ObjectId,
      required: true
    },
    data: {},
    transactions: transactions
  });

  Statistic.index({
    'org.type': 1,
    'org.id': 1,
    consumerId: 1
  }, {
    unique: true
  });

  Statistic.index({
    consumerId: 1,
    "org.id": 1
  });

  Statistic.index({
    consumerId: 1,
    "org.type": 1,
    "org.id": 1
  });

  Statistic.index({
    'org.type': 1,
    'org.id': 1,
    consumerId: 1,
    "transactions.ids": 1
  });

  Statistic.index({
    'org.type': 1,
    'org.id': 1,
    consumerId: 1,
    "data.tapIns.totalTapIns": 1
  });

  Statistic.index({
    'org.type': 1,
    'org.id': 1,
    consumerId: 1,
    "data.tapIns.totalAmountPurchased": 1
  });

  Statistic.index({
    'org.type': 1,
    'org.id': 1,
    consumerId: 1,
    "data.tapIns.lastVisited": 1
  });

  Statistic.index({
    'org.type': 1,
    'org.id': 1,
    consumerId: 1,
    "data.tapIns.firstVisited": 1
  });

  Statistic.index({
    'org.type': 1,
    'org.id': 1,
    consumerId: 1,
    "data.tapIns.totalDonated": 1
  });

  Statistic.index({
    'org.type': 1,
    'org.id': 1,
    consumerId: 1,
    "data.polls.totalAnswered": 1
  });

  Statistic.index({
    'org.type': 1,
    'org.id': 1,
    consumerId: 1,
    "data.polls.lastAnsweredDate": 1
  });

  Statistic.index({
    'org.type': 1,
    'org.id': 1,
    consumerId: 1,
    "data.karmaPoints.earned": 1
  });

  Statistic.index({
    'org.type': 1,
    'org.id': 1,
    consumerId: 1,
    "data.karmaPoints.remaining": 1
  });

  Statistic.index({
    'org.type': 1,
    'org.id': 1,
    consumerId: 1,
    "data.karmaPoints.used": 1
  });

  UnclaimedBarcodeStatistic = new Schema({
    org: organization,
    barcodeId: {
      type: String,
      required: true
    },
    data: {},
    claimId: {
      type: ObjectId
    }
  });

  UnclaimedBarcodeStatistic.index({
    'org.type': 1,
    'org.id': 1,
    barcodeId: 1
  }, {
    unique: true
  });

  UnclaimedBarcodeStatistic.index({
    claimId: 1,
    barcodeId: 1
  });

  UnclaimedBarcodeStatistic.index({
    'org.type': 1,
    'org.id': 1,
    barcodeId: 1,
    "transactions.ids": 1
  });

  UnclaimedBarcodeStatistic.index({
    "transactions.ids": 1
  });

  UnclaimedBarcodeStatistic.index({
    'org.type': 1,
    'org.id': 1,
    barcodeId: 1,
    "data.tapIns.totalTapIns": 1
  });

  UnclaimedBarcodeStatistic.index({
    'org.type': 1,
    'org.id': 1,
    barcodeId: 1,
    "data.tapIns.totalAmountPurchased": 1
  });

  UnclaimedBarcodeStatistic.index({
    'org.type': 1,
    'org.id': 1,
    barcodeId: 1,
    "data.tapIns.lastVisited": 1
  });

  UnclaimedBarcodeStatistic.index({
    'org.type': 1,
    'org.id': 1,
    barcodeId: 1,
    "data.tapIns.firstVisited": 1
  });

  UnclaimedBarcodeStatistic.index({
    'org.type': 1,
    'org.id': 1,
    barcodeId: 1,
    "data.tapIns.totalDonated": 1
  });

  UnclaimedBarcodeStatistic.index({
    'org.type': 1,
    'org.id': 1,
    consumerId: 1,
    "data.karmaPoints.earned": 1
  });

  UnclaimedBarcodeStatistic.index({
    'org.type': 1,
    'org.id': 1,
    consumerId: 1,
    "data.karmaPoints.remaining": 1
  });

  UnclaimedBarcodeStatistic.index({
    'org.type': 1,
    'org.id': 1,
    consumerId: 1,
    "data.karmaPoints.used": 1
  });

  CardRequest = new Schema({
    entity: {
      type: {
        type: String,
        required: true,
        "enum": choices.entities._enum
      },
      id: {
        type: ObjectId,
        required: true
      }
    },
    dates: {
      requested: {
        type: Date,
        required: true
      },
      responded: {
        type: Date
      }
    }
  });

  EmailSubmission = new Schema({
    entity: {
      type: {
        type: String,
        required: true,
        "enum": choices.entities._enum
      }
    },
    barcodeId: {
      type: String
    },
    businessId: {
      type: ObjectId,
      required: true
    },
    registerId: {
      type: ObjectId,
      required: true
    },
    locationId: {
      type: ObjectId,
      required: true
    },
    email: {
      type: String,
      validate: Email,
      required: true
    },
    date: {
      type: Date,
      required: true
    }
  });

  exports.DBTransaction = mongoose.model('DBTransaction', DBTransaction);

  exports.Sequence = mongoose.model('Sequence', Sequence);

  exports.Consumer = mongoose.model('Consumer', Consumer);

  exports.Client = mongoose.model('Client', Client);

  exports.Business = mongoose.model('Business', Business);

  exports.Poll = mongoose.model('Poll', Poll);

  exports.Goody = mongoose.model('Goody', Goody);

  exports.Discussion = mongoose.model('Discussion', Discussion);

  exports.Response = mongoose.model('Response', Response);

  exports.Media = mongoose.model('Media', Media);

  exports.ClientInvitation = mongoose.model('ClientInvitation', ClientInvitation);

  exports.Tag = mongoose.model('Tag', Tag);

  exports.EventRequest = mongoose.model('EventRequest', EventRequest);

  exports.Stream = mongoose.model('Stream', Stream);

  exports.Event = mongoose.model('Event', Event);

  exports.BusinessTransaction = mongoose.model('BusinessTransaction', BusinessTransaction);

  exports.BusinessRequest = mongoose.model('BusinessRequest', BusinessRequest);

  exports.PasswordResetRequest = mongoose.model('PasswordResetRequest', PasswordResetRequest);

  exports.Statistic = mongoose.model('Statistic', Statistic);

  exports.UnclaimedBarcodeStatistic = mongoose.model('UnclaimedBarcodeStatistic', UnclaimedBarcodeStatistic);

  exports.Organization = mongoose.model('Organization', Organization);

  exports.Referral = mongoose.model('Referral', Referral);

  exports.Barcode = mongoose.model('Barcode', Barcode);

  exports.CardRequest = mongoose.model('CardRequest', CardRequest);

  exports.EmailSubmission = mongoose.model('EmailSubmission', EmailSubmission);

  exports.RedemptionLog = mongoose.model('RedemptionLog', RedemptionLog);

  exports.schemas = {
    Sequence: Sequence,
    Consumer: Consumer,
    Client: Client,
    Business: Business,
    Poll: Poll,
    Goody: Goody,
    Discussion: Discussion,
    Response: Response,
    Media: Media,
    ClientInvitation: ClientInvitation,
    Tag: Tag,
    EventRequest: EventRequest,
    Stream: Stream,
    Event: Event,
    BusinessTransaction: BusinessTransaction,
    BusinessRequest: BusinessRequest,
    PasswordResetRequest: PasswordResetRequest,
    Statistic: Statistic,
    UnclaimedBarcodeStatistic: UnclaimedBarcodeStatistic,
    Organization: Organization,
    Referral: Referral,
    Barcode: Barcode,
    CardRequest: CardRequest,
    EmailSubmission: EmailSubmission,
    RedemptionLog: RedemptionLog
  };

}).call(this);
