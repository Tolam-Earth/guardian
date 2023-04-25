import { loggerAPI } from '@api/logger.service';
import { Log } from '@entity/log';
import {
    ApplicationState,
    COMMON_CONNECTION_CONFIG,
    DataBaseHelper,
    MessageBrokerChannel,
    Migration
} from '@guardian/common';
import { ApplicationStates } from '@guardian/interfaces';
import { MikroORM } from '@mikro-orm/core';
import { MongoDriver } from '@mikro-orm/mongodb';

Promise.all([
    Migration({
        ...COMMON_CONNECTION_CONFIG,
        migrations: {
            path: 'dist/migrations',
            transactional: false
        }
    }),
    MikroORM.init<MongoDriver>({
        ...COMMON_CONNECTION_CONFIG,
        driverOptions: {
            useUnifiedTopology: true
        },
        ensureIndexes: true
    }),
    MessageBrokerChannel.connect('LOGGER_SERVICE'),
]).then(async values => {
    const [_, db, mqConnection] = values;
    DataBaseHelper.orm = db;
    const state = new ApplicationState();
    await state.setServiceName('LOGGER_SERVICE').setConnection(mqConnection).init();
    state.updateState(ApplicationStates.STARTED);
    const logRepository = new DataBaseHelper(Log);

    state.updateState(ApplicationStates.INITIALIZING);
    await loggerAPI(mqConnection, logRepository);

    state.updateState(ApplicationStates.READY);
    // const maxPayload = parseInt(process.env.MQ_MAX_PAYLOAD, 10);
    // if (Number.isInteger(maxPayload)) {
    //     new LargePayloadContainer().runServer();
    // }
    console.log('logger service started', await state.getState());
}, (reason) => {
    console.log(reason);
    process.exit(0);
})
