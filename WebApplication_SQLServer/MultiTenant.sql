USE [Multitenant]
GO

/****** Object:  Table [dbo].[AppTenant]    Script Date: 23/03/2020 11:29:52 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [dbo].[AppTenant](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[key] [nvarchar](40) NULL,
	[hostname] [nvarchar](255) NOT NULL,
	[connectionstring] [nvarchar](1000) NULL,
	[connectionstringwindows] [nvarchar](1000) NULL,
	[Version] [nvarchar](40) NOT NULL,
	[DBName] [nvarchar](255) NULL,
	[BetaChannel] [bit] NULL,
	[NoAutoUpgrades] [bit] NULL,
	[TestInstance] [bit] NULL,
	[certhash] [nvarchar](255) NULL,
	[DoNHServer] [bit] NULL,
	[AreaName] [nvarchar](255) NULL,
	[NHServerVersion] [nvarchar](11) NULL,
	[TargetVersion] [nvarchar](40) NOT NULL,
	[UpgradeDate] [datetime] NULL,
	[LastLogin] [datetime] NULL,
	[VersionSuffix] [varchar](10) NULL,
	[IsWebAppRunning] [bit] NULL,
	[deployment_id] [int] NULL,
	[monitor] [bit] NULL,
	[location] [nvarchar](10) NULL,
	[smtphostname] [nvarchar](100) NULL,
	[versiongroup] [nvarchar](10) NULL,
	[alias] [nvarchar](50) NULL,
	[dointegrator] [bit] NOT NULL,
	[SnoozeDate] [datetime] NULL,
	[dblocation] [varchar](20) NULL,
	[parent_apptenant_id] [int] NULL,
	[appsnoozedate] [datetime] NULL,
	[envName] [nvarchar](50) NULL,
	[DBID] [uniqueidentifier] NULL,
	[lastrestored] [datetime] NULL,
	[AppVersionsDNSID] [int] NULL,
	[VersionGroupFixed] [bit] NOT NULL,
	[source_apptenant_id] [int] NULL,
	[db_status] [int] NULL,
	[redisHash] [nvarchar](10) NULL,
 CONSTRAINT [PK__AppTenan__3213E83F22E08109] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

ALTER TABLE [dbo].[AppTenant] ADD  CONSTRAINT [DF_AppTenant_location]  DEFAULT ('UK') FOR [location]
GO

ALTER TABLE [dbo].[AppTenant] ADD  CONSTRAINT [DF_AppTenant_smtphostname]  DEFAULT ('d3ukmail.nethelpdesk.com') FOR [smtphostname]
GO

ALTER TABLE [dbo].[AppTenant] ADD  DEFAULT ((0)) FOR [dointegrator]
GO

ALTER TABLE [dbo].[AppTenant] ADD  DEFAULT (getutcdate()) FOR [SnoozeDate]
GO

ALTER TABLE [dbo].[AppTenant] ADD  DEFAULT ((0)) FOR [parent_apptenant_id]
GO

ALTER TABLE [dbo].[AppTenant] ADD  DEFAULT (getutcdate()) FOR [appsnoozedate]
GO

ALTER TABLE [dbo].[AppTenant] ADD  DEFAULT ('') FOR [envName]
GO

CREATE TABLE [dbo].[AppTenantPortal](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[apptenant_id] [int] NOT NULL,
	[hostname] [nvarchar](100) NOT NULL,
	[certhash] [varchar](100) NULL,
	[clientidoverride] [nvarchar](450) NULL,
	[alias] [nvarchar](50) NULL,
PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, OPTIMIZE_FOR_SEQUENTIAL_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]
GO

CREATE TABLE [dbo].[EventLog](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[EventID] [int] NULL,
	[Level] [nvarchar](50) NULL,
	[Message] [nvarchar](max) NULL,
	[Name] [nvarchar](255) NULL,
	[TimeStamp] [datetimeoffset](7) NULL,
	[Host] [nvarchar](255) NULL,
	[Path] [nvarchar](255) NULL,
	[QueryString] [nvarchar](1000) NULL,
	[Method] [nvarchar](255) NULL,
	[User] [nvarchar](255) NULL,
	[ServerHostname] [nvarchar](255) NULL,
	[Version] [nvarchar](50) NULL,
 CONSTRAINT [PK__EventLog__3214EC2798C759DE] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO


CREATE TABLE [dbo].[DataProtectionKeys](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[FriendlyName] [nvarchar](max) NULL,
	[Xml] [nvarchar](max) NULL,
 CONSTRAINT [PK_DataProtectionKeys] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO


CREATE TABLE [dbo].[NHD_IDENTITY_Application](
	[Id] [nvarchar](450) NOT NULL,
	[ClientId] [nvarchar](450) NULL,
	[ClientSecret] [nvarchar](max) NULL,
	[DisplayName] [nvarchar](max) NULL,
	[LogoutRedirectUri] [nvarchar](max) NULL,
	[RedirectUri] [nvarchar](max) NULL,
	[Type] [nvarchar](max) NULL,
	[Discriminator] [nvarchar](max) NULL,
	[RedirectUris] [nvarchar](max) NULL,
	[PostLogoutRedirectUris] [nvarchar](max) NULL,
	[ConcurrencyToken] [nvarchar](50) NULL,
	[ConsentType] [nvarchar](max) NULL,
	[Properties] [nvarchar](max) NULL,
	[Permissions] [nvarchar](max) NULL,
	[GrantType] [nvarchar](50) NULL,
	[AllowAgents] [bit] NULL,
	[AllowUsers] [bit] NULL,
	[OrganisationID] [int] NULL,
	[AreaID] [int] NULL,
 CONSTRAINT [PK_NHD_IDENTITY_Application] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

ALTER TABLE [dbo].[NHD_IDENTITY_Application] ADD  CONSTRAINT [DF_NHD_IDENTITY_Application_AllowAgents]  DEFAULT ((1)) FOR [AllowAgents]
GO

ALTER TABLE [dbo].[NHD_IDENTITY_Application] ADD  CONSTRAINT [DF_NHD_IDENTITY_Application_AllowUsers]  DEFAULT ((0)) FOR [AllowUsers]
GO

ALTER TABLE [dbo].[NHD_IDENTITY_Application] ADD  CONSTRAINT [DF_NHD_IDENTITY_Application_OrganisationID]  DEFAULT ((0)) FOR [OrganisationID]
GO

ALTER TABLE [dbo].[NHD_IDENTITY_Application] ADD  CONSTRAINT [DF_NHD_IDENTITY_Application_AreaID]  DEFAULT ((0)) FOR [AreaID]
GO


CREATE TABLE [dbo].[NHD_IDENTITY_Authorization](
	[Id] [nvarchar](450) NOT NULL,
	[ApplicationId] [nvarchar](450) NULL,
	[Scope] [nvarchar](max) NULL,
	[Subject] [nvarchar](max) NULL,
	[ConcurrencyToken] [nvarchar](max) NULL,
	[Scopes] [nvarchar](max) NULL,
	[Properties] [nvarchar](max) NULL,
	[Status] [nvarchar](max) NULL,
	[Type] [nvarchar](max) NULL,
 CONSTRAINT [PK_NHD_IDENTITY_Authorization] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

ALTER TABLE [dbo].[NHD_IDENTITY_Authorization]  WITH CHECK ADD  CONSTRAINT [FK_NHD_IDENTITY_Authorization_NHD_IDENTITY_Application_ApplicationId] FOREIGN KEY([ApplicationId])
REFERENCES [dbo].[NHD_IDENTITY_Application] ([Id])
GO

ALTER TABLE [dbo].[NHD_IDENTITY_Authorization] CHECK CONSTRAINT [FK_NHD_IDENTITY_Authorization_NHD_IDENTITY_Application_ApplicationId]
GO


CREATE TABLE [dbo].[NHD_IDENTITY_Scope](
	[Id] [nvarchar](450) NOT NULL,
	[Description] [nvarchar](max) NULL,
	[ConcurrencyToken] [nvarchar](max) NULL,
	[DisplayName] [nvarchar](max) NULL,
	[Name] [nvarchar](max) NULL,
	[Properties] [nvarchar](max) NULL,
	[Resources] [nvarchar](max) NULL,
 CONSTRAINT [PK_NHD_IDENTITY_Scope] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

CREATE TABLE [dbo].[NHD_IDENTITY_Token](
	[Id] [nvarchar](450) NOT NULL,
	[ApplicationId] [nvarchar](450) NULL,
	[AuthorizationId] [nvarchar](450) NULL,
	[Subject] [nvarchar](max) NULL,
	[Type] [nvarchar](max) NULL,
	[ConcurrencyToken] [nvarchar](max) NULL,
	[Payload] [nvarchar](max) NULL,
	[Properties] [nvarchar](max) NULL,
	[ReferenceId] [nvarchar](max) NULL,
	[Status] [nvarchar](max) NULL,
	[CreationDate] [datetimeoffset](7) NULL,
	[ExpirationDate] [datetimeoffset](7) NULL,
 CONSTRAINT [PK_NHD_IDENTITY_Token] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

ALTER TABLE [dbo].[NHD_IDENTITY_Token]  WITH CHECK ADD  CONSTRAINT [FK_NHD_IDENTITY_Token_NHD_IDENTITY_Application_ApplicationId] FOREIGN KEY([ApplicationId])
REFERENCES [dbo].[NHD_IDENTITY_Application] ([Id])
GO

ALTER TABLE [dbo].[NHD_IDENTITY_Token] CHECK CONSTRAINT [FK_NHD_IDENTITY_Token_NHD_IDENTITY_Application_ApplicationId]
GO

ALTER TABLE [dbo].[NHD_IDENTITY_Token]  WITH CHECK ADD  CONSTRAINT [FK_NHD_IDENTITY_Token_NHD_IDENTITY_Authorization_AuthorizationId] FOREIGN KEY([AuthorizationId])
REFERENCES [dbo].[NHD_IDENTITY_Authorization] ([Id])
GO

ALTER TABLE [dbo].[NHD_IDENTITY_Token] CHECK CONSTRAINT [FK_NHD_IDENTITY_Token_NHD_IDENTITY_Authorization_AuthorizationId]
GO

CREATE TABLE [dbo].[NHD_User](
	[ID] [nvarchar](450) NOT NULL,
	[AccessFailedCount] [int] NOT NULL,
	[ConcurrencyStamp] [nvarchar](max) NULL,
	[Email] [nvarchar](256) NULL,
	[EmailConfirmed] [bit] NOT NULL,
	[LockoutEnabled] [bit] NOT NULL,
	[LockoutEnd] [datetimeoffset](7) NULL,
	[NormalizedEmail] [nvarchar](256) NULL,
	[NormalizedUserName] [nvarchar](256) NULL,
	[PasswordHash] [nvarchar](max) NULL,
	[PhoneNumber] [nvarchar](max) NULL,
	[PhoneNumberConfirmed] [bit] NOT NULL,
	[SecurityStamp] [nvarchar](max) NULL,
	[TwoFactorEnabled] [bit] NOT NULL,
	[Uid] [int] NOT NULL,
	[Unum] [int] NOT NULL,
	[UserName] [nvarchar](256) NULL,
	[Salt] [nvarchar](255) NULL,
	[Iterations] [int] NULL,
	[WindowsUsername] [nvarchar](255) NULL,
	[Disabled] [bit] NOT NULL,
	[AccountConfirmed] [bit] NULL,
	[ResetPassword] [bit] NULL,
 CONSTRAINT [PK_NHD_User] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

ALTER TABLE [dbo].[NHD_User] ADD  DEFAULT ((1)) FOR [AccountConfirmed]
GO

ALTER TABLE [dbo].[NHD_User] ADD  DEFAULT ((0)) FOR [ResetPassword]
GO

INSERT INTO [dbo].[NHD_IDENTITY_Application]
           ([Id]
           ,[ClientId]
           ,[ClientSecret]
           ,[DisplayName]
           ,[Type]
           ,[Discriminator])
     VALUES
           ('bce11b94-c656-40b3-a928-b2c4b813803f'
           ,'nethelpdesk-resource-server'
           ,'AQAAAAEAACcQAAAAEH+NWbcAmDHulwR+CZdanSkfetwpDTU4b2fgLGWMxybcWOsDnDS8+sSIfvmPWMGrww=='
           ,'nethelpdesk-resource-server'
           ,'confidential'
           ,'NHD_Identity_Application')
GO
