#region Copyright © 2010, Blue Dot Solutions

// *********************************************************************
// 
// Copyright © 2010, Blue Dot Solutions and/or its affiliates 
// and subsidiaries.  All rights reserved.
// www.bluedotsolutions.com
//       
// Blue Dot Solutions has intellectual property rights relating  
// to technology embodied in this product. In particular, and 
// without limitation, these intellectual property rights may 
// include one or more of U.S. patents or pending patent applications
// in the U.S. and/or other countries.
//      
// This product is distributed under licenses restricting its use, 
// copying, distribution, and decompilation. No part of this product 
// may be reproduced in any form by any means without prior written 
// authorization of Blue Dot Solutions.
//       
// Blue Dot, mNOW!, mNOW! Mobile Framework, mCORE!, mfLY!,
// mCORE! Command Center, mCORE! Communication Agent, mCORE! 
// Communication Server, and mCORE! Integration Engine are trademarks of 
// Blue Dot Solutions.
//  
// *********************************************************************

#endregion

using System;
using System.Configuration;
using System.Diagnostics;
using System.IO;
using System.Management.Automation;
using System.Net;

namespace Pstrano.Automation
{
    [Cmdlet(VerbsCommunications.Write, "EnvironmentConfiguration")]
    public class WriteEnvironmentConfiguration : Cmdlet
    {
        #region Properties

        [Parameter(Mandatory = true, Position = 0)]
        public string ConfigurationFilePath { get; set; }

        [Parameter(Mandatory = true, Position = 1)]
        public string Environment { get; set; }

        [Parameter(Mandatory = false)]
        [Switch("Throw", typeof(Boolean))]
        public bool ThrowExceptionOnErrors { get; set; }

        #endregion

        #region private

        private static void GenerateEnvironmentConfiguration(Configuration envConfig, Configuration mainConfig)
        {
            // Connection strings
            foreach (ConnectionStringSettings connectionString in envConfig.ConnectionStrings.ConnectionStrings)
            {
                if (connectionString.Name == "LocalSqlServer") continue;
                mainConfig.ConnectionStrings.ConnectionStrings[connectionString.Name].ConnectionString =
                    connectionString.ConnectionString;
            }

            // app settings
            foreach (KeyValueConfigurationElement setting in envConfig.AppSettings.Settings)
            {
                mainConfig.AppSettings.Settings[setting.Key].Value = setting.Value;
            }

            // applicationSettings
            var group = envConfig.GetSectionGroup("applicationSettings");
            if (group != null)
            {
                foreach (ConfigurationSection section in group.Sections)
                {
                    if (!(section is ClientSettingsSection)) continue;

                    var s = (ClientSettingsSection)section;

                    var mainGroup = mainConfig.GetSectionGroup("applicationSettings");
                    if (mainGroup == null)
                    {
                        mainConfig.SectionGroups.Add("applicationSettings", group);
                        break;
                    }

                    var mainS = mainGroup.Sections.Get(s.SectionInformation.Name) as ClientSettingsSection;
                    if (mainS == null)
                    {
                        mainGroup.Sections.Add(s.SectionInformation.Name, s);
                    }
                    else
                    {
                        foreach (SettingElement setting in s.Settings)
                        {
                            var toRemove = mainS.Settings.Get(setting.Name);
                            if (toRemove != null)
                            {
                                mainS.Settings.Remove(toRemove);
                            }

                            mainS.Settings.Add(setting);
                        }
                    }
                }
            }

            mainConfig.Save();
        }

        private void LogDebug(string message, params object[] paramters)
        {
            WriteObject(string.Format("[{0}]# ", Dns.GetHostName()) + string.Format(message, paramters));
        }

        private void LogWarn(string message, params object[] paramters)
        {
            WriteWarning(string.Format("[{0}]# ", Dns.GetHostName()) + string.Format(message, paramters));
            if (ThrowExceptionOnErrors)
            {
                throw new ApplicationException(string.Format(message, paramters));
            }
        }

        #endregion

        #region protected

        protected override void ProcessRecord()
        {
            LogDebug("Writing configuration for environment '{0}' using base configuration file '{1}'.", Environment, ConfigurationFilePath);

            if (!File.Exists(ConfigurationFilePath))
            {
                LogWarn("Configuration file '{0}' was not found.", ConfigurationFilePath);
                return;
            }

            var envConfigurationFile = Path.Combine(Path.GetDirectoryName(ConfigurationFilePath),
                                                    string.Format(@"AppConfig\{0}.config",
                                                                  Environment.ToLowerInvariant()));

            if (!File.Exists(envConfigurationFile))
            {
                LogWarn("Environment configuration file '{0}' was not found.", envConfigurationFile);
                return;
            }

            LogDebug("Using configuration file '{0}'. ", envConfigurationFile);

            var envConfig = ConfigurationManager.OpenMappedExeConfiguration(
                new ExeConfigurationFileMap { ExeConfigFilename = envConfigurationFile }, ConfigurationUserLevel.None);

            if (ConfigurationFilePath.ToLowerInvariant().EndsWith("web.config"))
            {
                var mainConfig = ConfigurationManager.OpenMappedExeConfiguration(
                    new ExeConfigurationFileMap { ExeConfigFilename = ConfigurationFilePath },
                    ConfigurationUserLevel.None);

                GenerateEnvironmentConfiguration(envConfig, mainConfig);
            }
            else
            {
                var exe = ConfigurationFilePath.Replace(".config", string.Empty);
                if (!File.Exists(exe))
                {
                    LogWarn(
                        "Executable '{0}' was not found. App.config files can only be written for a specific environment with a valid exe.",
                        exe);
                    return;
                }

                var mainConfig = ConfigurationManager.OpenExeConfiguration(exe);

                GenerateEnvironmentConfiguration(envConfig, mainConfig);
            }
        }

        #endregion
    }
}